# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C — execution packet: the POS card Edge transport (local, fake-only)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C` (a ticket of the umbrella
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md); its §4 row "Shared transport capability" and
the [IMPLEMENTATION_CHECKLIST](IMPLEMENTATION_CHECKLIST.md) row of the same Work ID). Controlling contract:
[API_CONTRACT](API_CONTRACT.md) §4.55 with **D-051** .. **D-064**; the Edge function this transport calls is described by
[the 001E execution packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md) (§4 HTTP surface, §5 constants and worst
cases) and `supabase/functions/pos-card-charge/CONTRACT.md`. This packet records no **DECISION**, adds no **OPEN
QUESTION** and allocates no ID.

**Corrected** by `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C-TRANSPORT-CORRECTIONS-001` (§13): the HTTP status policy of §5.4 is
closed, and `data_remote` and the POS app declare the `http`, `logging` and `supabase` dependencies they import (§7).
Sections 8, 9 and 11 keep the record of 001C as reviewed at `71bfef5b`; §10 shows the corrected rows.

## 1. Authorization and boundary

- Command-room authorization of 2026-10-29, "LOCAL CARD EDGE TRANSPORT, FAKE-ONLY": the unwired Z-Credit source
  profile candidate is accepted locally at `cf1ffacf7f1395a66d653f0a5862c0d6e1622546` (tree
  `837be56f053115060915063091fd9cbffba0f55f`; review package `1c0f122aefffc13b14191ca05d484d1bd1ee9daa4ecf4b8b1fab19f13c5acfea`)
  with no correction round. The instruction is kept outside Git with a SHA-256 sidecar
  (`1edf5049847d59275db82aba7e335bfb96015144df3aa2530a0985b340fca479`).
- Purpose: ONE dedicated POS-to-Edge transport capability for the `pos-card-charge` function. It sends one
  authenticated request, applies a dedicated payment-call timeout, returns the response or a transport failure,
  preserves the request bytes and identity and never retries automatically. It does not select provider credentials,
  derive provider keys, classify provider replies, record a payment, poll in the background, wire the provider profile
  or operate a device; and it adds no provider or terminal abstraction beyond this one seam.
- Allowed: `packages/data_remote` (the capability interface, the Supabase implementation, upgradable / guarded
  forwarding, focused tests), `packages/auth_identity` (`DeviceSessionGuardedTransport` forwarding and guard tests), a
  POS boot-composition test where needed to prove both real compositions expose the capability, and this packet.
- Not modified: `supabase/functions/pos-card-charge/**` (`index.ts` keeps `providerProfile: null`), migrations, SQL
  tests, `config.toml`, CI, payment writers or schema, the POS payment UI, the attempt journal, l10n, Dashboard, KDS,
  Kiosk, Storefront, web orders, printing, releases, and every dependency manifest or lockfile (in 001C; the
  correction of §13 adds four direct declarations to two manifests).
- **Recorded narrowings and deviations** (none silent):
  - The [IMPLEMENTATION_CHECKLIST](IMPLEMENTATION_CHECKLIST.md) row and the pilot's §7 allowlist give 001C
    `packages/l10n` ARBs, and the [TESTING_STRATEGY](TESTING_STRATEGY.md) 001C / 001F lane names ar / he / en strings.
    This authorization forbids l10n: 001C adds no user-visible string (its failure reasons are closed, internal,
    never-displayed diagnostics), and the ar / he / en strings for transport outcomes move to 001F, which owns the UI.
    Aligning the checklist row and the pilot §7 text is an open documentation item for a separately approved change;
    this ticket edits neither.
  - `apps/pos/test` is added by this authorization (tests only), for the composition proof.
  - `packages/data_remote/lib/src/kitchen_ack_http_boundary.dart` is changed: it is the POS client's HTTP boundary,
    part of the Supabase implementation, and the only place below the SDK where one handoff can be enforced (§5.3).
  - The base is a local stack that `origin/main` does not contain; 001C depends on the unmerged 001D / 001E contract
    (its static test reads 001E's constants), so it can merge only after them.
  - Followed literally: authorization §6 keeps a timeout or a lost connection transport-unknown. The design check
    (§8) had a deadline that passes before the HTTP handoff reported `notSent`; the delta review (§11) found that this
    departs from §6, so once the SDK call has started only the gate's own refusal is `notSent`, and every timeout is
    `uncertain` (§5.4).
- Process: no push, PR, merge, "Update branch", hosted action, deployment, secret or configuration change, provider
  request, terminal or card action, printer or APK action; no amend, rebase, reset or history rewrite; no Codex review;
  one fresh-context Claude delta review (§11); fake or loopback HTTP only, and unexpected network access fails the
  tests; no background monitor.
- Branch `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C-card-edge-transport`, created at `cf1ffacf` in its own worktree,
  stacked on the unmerged profile-candidate (`cf1ffacf`), D-064 (`ca8edb03`), W1 (`140be040`), G1 (`295cacb6`), 001E
  (`d5456624`) and #370 (`54b19ab5`) heads; local only. `main` is recorded separately (§2) and is not merged into
  this stack.

## 2. Source anchor (preflight 2026-10-29T08:35:26Z, read-only)

| Item | Value |
|---|---|
| Base | `cf1ffacf…` (tree `837be56f…`, parent `5531256c513e3d4c523b9278ac9f2c0e64bf3dc9`); the new branch points at it with no commit on top before this packet; clean worktree, no upstream; `index.ts` line 19 `providerProfile: null,` |
| Earlier heads | profile candidate `cf1ffacf` (worktree clean, tree `837be56f`), D-064 `ca8edb03`, W1 `140be040` (tree `cbfda1f5`), G1 `295cacb6`, 001E `d5456624`: every branch and worktree unchanged and clean; 001E and #370 are ancestors of the base |
| #370 / #371 | OPEN drafts at `54b19ab58ce72a2fa9a43860e31181a08222b254` / `53d6a6adc38f308b7ed6b0dd62177e6edd5ad5ce` |
| Accepted package | the profile-candidate review ZIP verifies against its sidecar; its evidence folder's `SHA256SUMS.txt` verifies 60 / 60 |
| main | the main checkout at `556136f1` with no tracked change; actual `origin/main` = `435ada86fe10c00c94c0fdfdb0395559587489eb` (`git ls-remote`); merge base with this stack `d2079820`; the 7 main commits since it change 44 files, none in this ticket's file set (§4), none under `packages/auth_identity` or `apps/pos/lib/main.dart` |
| Ownership | no open PR and no dirty worktree touches the owned files. Two stale local branches hold one commit each on `device_session_guarded_transport.dart` outside the base's history — `fix/BIZBOT-DEVICE-SESSION-FIX-001-clients` (file commit `3c485e9e`, 2026-10-05; branch tip `6a3e4bae`) and `fix/BIZBOT-DEVICE-SESSION-FIX-001-r1-clients` (file commit and tip `271fbc7e`, 2026-10-06), no PR — whose work reached `main` as `7c0609aa` / `014c4d81`; the file has since changed on `main` three more times (`e1efdd46`, `12a95b88` — the #358 / #359 guard-forwarding lesson —, `f4f524cd`) and is identical at the base and at `origin/main`. They are not active ownership |
| Remote | no remote ref, PR or other local branch names this Work ID |
| Baselines at the base | `dart test packages/data_remote` 40 / 40; `dart test packages/auth_identity` 140 / 140; `flutter test apps/pos/test/online_order_inbox_guarded_composition_test.dart` 23 / 23; the `pos-card-charge` Node suite 187 / 187 on Node 22.14.0 and on Node 24.19.0 |

## 3. The real transport surfaces (read at the base)

- **Seam and precedent.** `packages/data_remote/lib/src/sync_rpc_transport.dart` defines `SyncRpcTransport.invoke`
  and the Edge precedent `AuthenticatedWebOrderDecisionTransport.decideWebOrder(Map<String, dynamic> body)` — a narrow
  capability "over the SAME authenticated device client".
- **Supabase implementation.** `SupabaseSyncRpcTransport` (`supabase_sync_rpc_transport.dart`; with
  `realtime_invalidation_source.dart` one of the two SDK importers of the package, whatever its older doc comment says)
  implements both. `_invokeSdk` (RPC) and `decideWebOrder` (`functions.invoke('pos-web-order-decision', body:
  body).timeout(_timeout)`) share one constructor-default 15 s timeout. `createKitchenAckClient(url, publicKey, {inner,
  timeout, authOptions})` builds the SDK client over a `KitchenAckHttpBoundary` (an `http.BaseClient` below the SDK's
  `AuthHttpClient`) and the guarded transport. That boundary runs each protected ACK inside a Zone context and hands it
  to the HTTP client only while the context is active, at most once and with redirects off — "Future.timeout does not
  cancel the SDK's authentication Future. A late continuation must never resurrect an invocation that already ended."
- **Hold-then-upgrade.** `UpgradableSyncTransport` refuses every call with zero IO until its single `upgrade(real)`
  (`heldCallCount` counts the refusals) and then forwards `decideWebOrder` only when the real transport has that
  capability; guarded ACKs pass an `isCurrent` callback through it.
- **Guard.** `packages/auth_identity/lib/src/device_session_guarded_transport.dart`: `block()` / `allow()` (driven by
  the pairing repository's device-session verdicts); a blocked guard refuses protected calls with
  `device_session_unverified`; `decideWebOrder` is checked at entry only, while guarded ACKs are re-checked at the HTTP
  handoff through `isCurrent: () => !_blocked && isCurrent()`.
- **Both POS boot compositions** (`apps/pos/lib/main.dart`): the degraded offline boot builds
  `DeviceSessionGuardedTransport(UpgradableSyncTransport())` (`_tryBuildDegradedSeams`, line 591) and upgrades it in
  place with the session's transport (line 547); the online boot builds
  `DeviceSessionGuardedTransport(session.transport)` (`_realSeams`, line 635). The POS session comes from
  `SupabaseAuthBootstrap(config, guardKitchenAcknowledgements: true).createAnonymousDeviceSession()` (line 512-515),
  which uses `createKitchenAckClient` with the default inner client
  (`packages/auth_identity/lib/src/supabase_auth_bootstrap.dart` line 77). Both compositions hand the guard to
  `posAuthTransportProvider`. KDS, Kiosk, Dashboard and Admin build their transports with the generic constructor.
- **The SDK path** (locked: `supabase` 2.13.3, `functions_client` 2.6.3, `gotrue` 2.24.0, `http` 1.6.0,
  `realtime_client` 2.9.1, `postgrest` 2.7.4): `functions.invoke` builds one `http.Request` (a String body is sent as-is;
  `Content-Type` defaults to `text/plain` unless a content type is passed) and hands it to the SDK's `AuthHttpClient`,
  which awaits the current access token — refreshing an expired session first; gotrue retries a retryable refresh with
  back-off for about 10 s and the refresh cannot be interrupted — and then `putIfAbsent`s `Authorization: Bearer
  <current access token>` and `apikey`. After a non-retryable refresh failure gotrue removes the session and the SDK
  sends `Bearer <public key>`; the function answers 401. A non-2xx answer throws `FunctionException(status, details)`
  after the body is decoded (a malformed body throws `FormatException` first, and its status is lost). The SDK's FINEST
  record `Request: method url headers` is written before `AuthHttpClient` adds `Authorization` and `apikey`: it holds no
  body and no credential, and the apps attach no log listener. dart:io re-sends a POST only for a 303 redirect (as a
  GET to its `Location`) and for an authentication challenge when credentials are configured (none are); IOClient opens
  the connection (DNS, TCP, TLS; dart:io sets no connect timeout) before writing the request and honours an
  `AbortableRequest` trigger until the request is written. No app installs another HTTP client.
- **The Edge function's HTTP surface** (`handler.mjs`, `lib/envelope.mjs` `statusOf`): 403 `origin_not_allowed` for
  any `Origin` header, 404 `not_found`, 405 `method_not_allowed`, 401 `invalid_session`, 400 `invalid_request` — the
  boundary's own checks and the card RPCs' RETURNed refusals, each with no ledger effect of the request — 503
  `unavailable` / `provider_unavailable`, and 200 for every other typed answer `{ok:true, …}` or `{ok:false, error, …}`.
  A 503 can follow work that already executed (a claim, a recording or release mark, a provider release or lookup and
  its finish, a free-order write); `statusOf` never answers `invalid_request`, `invalid_session`, `provider_unavailable`
  or `unavailable` with 200, the handler answers `origin_not_allowed`, `not_found` and `method_not_allowed` only with
  403 / 404 / 405, and every `ok:true` envelope echoes the request's `attempt_id`.

## 4. Exact files

Library (6): `packages/data_remote/lib/src/card_charge_transport.dart` (new: the capability, its result types, the
dedicated timeout and the pure answer classifier); `packages/data_remote/lib/src/supabase_sync_rpc_transport.dart`
(implements it); `packages/data_remote/lib/src/kitchen_ack_http_boundary.dart` (the card route's one-handoff gate);
`packages/data_remote/lib/src/upgradable_sync_transport.dart` and
`packages/auth_identity/lib/src/device_session_guarded_transport.dart` (forwarding); and the export in
`packages/data_remote/lib/restoflow_data_remote.dart`.

Tests (8, new): `packages/data_remote/test/card_charge_transport_test.dart`, `card_charge_loopback_test.dart`,
`card_charge_static_test.dart`, `support/captured_timers.dart`, `support/no_network.dart`;
`packages/auth_identity/test/device_session_guarded_card_charge_test.dart`;
`apps/pos/test/card_charge_transport_composition_test.dart` and its fixture
`apps/pos/test/fixtures/card_charge_edge.mjs` (runs the real, unchanged handler offline with the master flag off).

This packet. Nothing else; `apps/pos/lib` is unchanged (both compositions gain the capability through the existing
wrappers).

## 5. Design

### 5.1 The capability

`AuthenticatedCardChargeTransport.sendCardCharge(Map<String, dynamic> body, {bool Function()? isCurrent})` returns a
sealed `CardChargeTransportResult` and never throws (the `SyncFailure` / ARCHITECTURE §9.2 convention, not
`decideWebOrder`'s exceptions):

- `CardChargeAnswered(body)` — HTTP 200 whose body is a JSON object with a boolean `ok` that belongs to this request,
  returned unread and deeply unmodifiable. 001F still validates the closed §4.55.4 envelope or refusal.
- `CardChargeTransportFailure(kind, reason, httpStatus?)` — no body: a status already decides the kind, and nothing in
  a body may turn an uncertain failure into anything else.

Implemented by `SupabaseSyncRpcTransport` (only the POS client of `createKitchenAckClient`; the generic constructor
answers `notSent` / `capabilityUnavailable` with zero IO), by `UpgradableSyncTransport` and by
`DeviceSessionGuardedTransport`. `posCardChargeTimeout` and `posCardChargeFunction` are its constants. A type check
`is AuthenticatedCardChargeTransport` is not a capability test (every guard implements it); 001F gates its UI on its
own lab toggle.

### 5.2 Request integrity and authority

- `POST {supabaseUrl}/functions/v1/pos-card-charge`, no query; the body is encoded once with `jsonEncode`
  synchronously at call time, and only those exact UTF-8 bytes can be handed off (the boundary compares them); the
  transport adds only `Content-Type: application/json` and never adds, removes or rewrites a field (attempt id,
  amount, keys, tenant scope).
- The caller JWT is the SDK's: `AuthHttpClient` adds the CURRENT session's access token and the public `apikey`. No
  credential, service-role value, provider host, terminal reference or key is held or added by the transport.
- Native only: IOClient sends no `Origin`; a web build refuses before any IO (`unsupportedPlatform`), because a
  browser would add the `Origin` the function refuses.
- No body is logged or printed; results print no body.

### 5.3 One exchange, one handoff, no retry

`SupabaseSyncRpcTransport.sendCardCharge` runs the SDK call inside `KitchenAckHttpBoundary.runCardCharge`, whose
Zone carries a `CardChargeExchange` permit (the ACK pattern). The boundary hands the card route to the HTTP client
only when ALL hold, with no await between the checks and the handoff:

1. it is inside a card exchange's Zone (a plain `functions.invoke('pos-card-charge')` is refused);
2. the exchange is active (not ended by its answer, failure or deadline), has not handed off yet, and the boundary is
   not closed;
3. it is exactly a POST to the exact endpoint, with no query or fragment, with exactly the exchange's bytes;
4. `isCurrent` holds — ONE composed check: the guard's `!_blocked`, the upgradable transport's
   `identical(_real, real)` (defensive: `upgrade` is once-only, so it cannot turn false) and, when a caller passes
   one, the caller's own check (the POS compositions pass none), asked AFTER the SDK's access-token step, at the
   handoff itself. A check that throws refuses the handoff too.

The boundary recognizes the card route fail-closed: any request that names `pos-card-charge` as a `/`-separated
component of its decoded path, query or fragment, in any letter case, on any origin. Such a request is handed off
only under the four conditions above and is otherwise refused, never passed through — also where the SDK's URL and the
boundary's endpoint are derived differently (a configured base URL with dot segments) or where a base URL with a query
or a fragment moves the function's name out of the path: that card call is refused before any IO.

The handed-off request is the same method, URL, headers and bytes as an `http.AbortableRequest` with
`followRedirects = false` (dart:io would otherwise answer a 303 with a second, GET request) whose abort trigger is the
exchange's end: a connection still opening when the exchange ends is aborted before any byte is written. The deadline
ends the exchange synchronously (`Future.timeout`'s `onTimeout`), so no handoff can follow it: a late access-token
refresh or a late continuation can never send the request. Nothing in 001C retries, re-sends, resumes, polls or arms a
timer other than the one deadline; a late answer is never read. gotrue's own refresh requests (to `/auth/v1/token`)
are the SDK's and never reach the card route.

### 5.4 Failure classification (one row per condition)

| Condition | Kind | Reason |
|---|---|---|
| guard blocked at entry, or the composed check false at the handoff (the guard's block, or a caller's own `isCurrent`; the upgradable transport's identity check cannot turn false) | `notSent` | `deviceSessionUnverified` |
| upgradable transport in hold mode | `notSent` (counted in `heldCallCount`) | `devicePrincipalPending` |
| no card-capable transport (generic constructor, missing capability) | `notSent` | `capabilityUnavailable` |
| web build | `notSent` | `unsupportedPlatform` |
| body not JSON-encodable | `notSent` | `unencodableBody` |
| the boundary refused (closed client; not exactly this POST, URL and bytes — a card route on another origin or path, or with a query or a fragment, included; or the composed check threw) | `notSent` | `handoffRefused` |
| the SDK could not prepare the access token (an `AuthException` before the handoff: its refresh could not reach the auth server — a lost connection) | `uncertain` | `accessTokenUnavailable` |
| the deadline passed before the handoff (nothing was handed off, and the ended exchange refuses any later handoff) | `uncertain` | `timeout` |
| any other error before the handoff (no known SDK path) | `uncertain` | `transport` |
| HTTP 200, a JSON object, a boolean `ok`, an `attempt_id` (when present) equal to the request's — required for `ok:true` — and not an `ok:false` with a token the function only sends with another status (`statusOf`'s four and the handler's 403 / 404 / 405 tokens) | `CardChargeAnswered` | — |
| any other HTTP 200 (not JSON, not an object, no boolean `ok`, empty, another content type, an event stream — cancelled unread —, another attempt, a non-200 token) | `uncertain` (status 200) | `malformedAnswer` |
| HTTP 401 | `unauthenticated` | `httpStatus` |
| HTTP 400, 403, 404 or 405 — a closed set: the statuses the function answers only before any ledger write (§13.2); a decoded body never changes a status's kind (one that cannot be decoded makes the answer `uncertain`, below) | `notApplied` | `httpStatus` |
| any other status: every other 4xx (407, 408, 409, 413, 415, 422, 425 and 429 among them), any 1xx, any non-200 2xx, any 3xx (never followed), any 5xx, a status outside 100–599 | `uncertain` | `httpStatus` |
| a body that cannot be decoded (malformed JSON, invalid UTF-8) after the handoff | `uncertain` (no status) | `malformedAnswer` |
| the deadline passed after the handoff | `uncertain` | `timeout` |
| a connection failure or reset, a TLS failure or any other error after the handoff | `uncertain` | `transport` |

For 001F's existing decision (`classifyTransportFailure` in `apps/pos/lib/src/data/payment_repository.dart`):
`notSent` (nothing was sent, and nothing can be) and `notApplied` (refused with no ledger effect of this request) are
"not applied" (the same attempt may be sent again), `unauthenticated` (refused with no ledger effect of this request)
is "auth required", `uncertain` is UNCONFIRMED (the same persisted attempt, a later `status`). Only a `notApplied`
400 / 403 / 404 / 405 or an `unauthenticated` 401 means "this request was refused with no ledger effect", never "the
attempt was not charged"; no other status means that (a proxy's or an intermediary's 407, 409, 413, 415 or 422
included), so every other status is UNCONFIRMED. No kind is a decline or an approval. 001F maps the kinds directly and
never re-derives an outcome from `httpStatus`: `classifyTransportFailure`'s numeric rule still treats any 4xx but 408 /
425 / 429 as not applied.
Once the SDK call has started, only the gate's own refusal is `notSent`: authorization §6 keeps every timeout and lost
connection transport-unknown, even one before the handoff, so 001F handles them all the same way.

### 5.5 The dedicated timeout: `posCardChargeTimeout` = 40 s

- **Derived, 31 s:** the largest configured 001E worst case is `release`: the 5 s request-body read + four 5 s RPC
  deadlines (proof, adapter read, release mark, finish) + the 6 s provider release (`constants.mjs` `TIMING`; 001E
  packet §5). The others: `start` 18 s, `status` 26 s, `free_order` 15 s.
- **Documented, +2 s:** the handler's own CPU time between those wall-clock deadlines is bounded by the platform's
  documented Edge limit of 2 s per request ([DEPLOYMENT](DEPLOYMENT.md) §17.4 item 2; pilot §2) = 33 s. How the hosted
  runtime accounts a worker's CPU is **OPEN QUESTION Q-039**; the documented per-request limit does not depend on it.
- **Engineering allowance, +7 s:** what no document bounds — connection setup, gateway routing and any request
  buffering there, worker start, other requests the same worker serves meanwhile, and the answer's return. It is a
  judgement, not a derived bound; the upload of the body is counted inside the function's 5 s read window, which
  assumes the gateway streams it rather than buffering it first (buffering falls to this allowance).
- **40 s.** One fixed value for every action, because the transport never reads the action. The deadline starts when
  the call starts, so the SDK's access-token step runs inside it; in production the SDK refreshes ahead of expiry, so
  that step is normally instant. A refresh that delays the handoff only shortens the time left: if the deadline passes
  before the handoff, nothing is ever sent (§5.3), and the failure is still `uncertain` / `timeout` like every timeout
  (authorization §6) — never a wrong certainty.
- It bounds one exchange, not the card payment: `start` answers within its 3 s window and the terminal interaction is
  followed through later `status` calls (initiate and poll). It is not the terminal's maximum payment time.
- The general 15 s timeout stays for RPC, `decideWebOrder` and ACKs. Changing 40 s needs a focused review and its tests:
  `card_charge_static_test.dart` recomputes 18 / 26 / 31 / 15 s from `constants.mjs` and pins the 2 s + 7 s margin.

### 5.6 What 001C deliberately leaves to others

- 001F: the attempt journal, persist-before-send, single-flight polling with back-off, the outcome UX and its ar / he /
  en strings, gating on the lab toggle, and treating `attempt_not_found` as inconclusive while a handed-off `start` may
  still be in flight (the POS's existing `PaymentAttemptStatusNotFound` rule).
- The function, the provider profile (`providerProfile: null`), every SQL object and every hosted step stay as they are.

## 6. Test plan (instruction §7 → tests)

| Instruction §7 item | Test (file) |
|---|---|
| both POS boot compositions expose the capability | online and degraded-then-upgraded boots expose the same guard through `posAuthTransportProvider`, and it sends one request (composition) |
| guarded and upgradable wrappers forward it | guard forwards once with the same body and passes `isCurrent` (guard); upgradable hold, upgrade, forward once, capability missing (transport) |
| an invalid / revoked device session refuses before Edge invocation | a blocked guard refuses at entry, and a block after the call started turns its handoff check false (guard, with a spy); a block during a gated token refresh, or right after the call (composition); a revoked restore verdict and a revoked heartbeat verdict each block the real composition's guard before the Edge invocation (composition) |
| a valid session forwards exactly once | one card-route request per call in every row (transport, loopback, composition) |
| the current caller authorization is forwarded | the current session's access token, switched between calls (transport); the composition's session token on the wire (composition); the guard test only proves forwarding of the body and the check (guard) |
| no service-role value exists client-side | static scan; the only `apikey` on the wire is the public key (static, transport) |
| the card call uses the dedicated timeout | the captured deadline is exactly `posCardChargeTimeout` (transport, composition) |
| ordinary sync / other Edge calls retain their current timeout | RPC and `decideWebOrder` arm 15 s; a configured general timeout leaves the card deadline at 40 s (transport, static) |
| the configured timeout exceeds every accepted 001E budget | recomputed from `constants.mjs` (static) |
| a fake handler completing within the budget succeeds | answered; the deadline is cancelled (transport) |
| a fake handler exceeding the deadline returns transport-unknown | `uncertain` / `timeout` after the handoff (transport, loopback, composition) |
| the test proves zero retry | every row of the transport test in which a card call fails or is refused runs in a timer-capturing Zone and, after a real settle (which runs any zero-delay or microtask work), proves that no timer it armed is still pending, that nothing periodic was armed and that it armed exactly its one deadline (none when refused before the SDK call) — before and after the handoff, the refusals, the direct-invoke spellings and the boundary unit included; the unreachable refresh runs its back-off waits only while the call is pending, and once the connection returns an ordinary call makes the SDK use it (the session is refreshed) and nothing is sent; the status, malformed, undecodable and post-handoff error rows also prove exactly one request (transport); the composition's failure rows prove the same through the boot guard (composition); the 303 redirect with its no-boundary control (loopback; the 301 / 302 / 307 / 308 and 401 / 407 rows are pins: dart:io would not re-send those either); mutants of re-sends after the handoff, only before it, after a refusal, on a deadline, on an escaping timer, on a Zone timer armed when the token step fails and waiting for the next token refresh are killed (§9) |
| a late fake response causes no second send | late answer after the deadline: still one request (transport, loopback, composition) |
| exact path and method; exact bytes or structural equality | wire bytes equal `jsonEncode(body)` (transport, loopback); the real handler accepts them (composition fixture) |
| attempt_id and other immutable fields unchanged | wire body equals the caller's map; the caller's map is unchanged (transport) |
| no Origin header for native POS | header set on the mock and on the wire (transport, loopback) |
| no body logging | Logger.root at ALL and print captured: no body or token value (transport) |
| authentication failures distinct from uncertain failures | 401 `unauthenticated`, also after a refused refresh signs the SDK out (transport); an unreachable refresh is a lost connection: `uncertain` / `accessTokenUnavailable`, zero card requests (transport) |
| unambiguous client / schema refusal distinct from timeout / socket / 5xx | the closed `notApplied` rows (400 / 403 / 404 / 405) vs the `uncertain` rows (14 other 4xx among them, plus 409 / 422 carrying `invalid_request` and a 407 HTML page), and the pure classifier over 503 non-200 statuses — every other 4xx included — with a synthetic body and with twelve answer shapes, with and without the attempt id (transport); the real handler's 400 (composition fixture) |
| malformed responses fail closed | the malformed-200 rows (20, the seven non-200 tokens written out) and the undecodable rows (transport) |
| no failure presented as decline or approval | closed kinds and reasons; a 503 claiming approval stays `uncertain` (transport) |
| providerProfile remains null; the candidate imported only by its tests | read-only checks of the function (static; the unchanged Node suite) |
| no provider host, credential, terminal id or card value enters Dart | static scans |
| no existing transport call changes behaviour | existing suites; RPC and other routes keep redirects and timeouts (transport, static) |
| no automatic retry loop, timer or background monitor added | the five card-path files, whole, against their pinned existing matches (five `for` loops and one message) for the constructs the static test names: any timer (a Zone's `createTimer` included); a Future constructed directly or through delayed, microtask, sync, doWhile, forEach, wait or any; a scheduled microtask; periodic work; a retry of any spelling; `for`, `while` and `do` loops; then, catchError, whenComplete and onError, typed or not; forEach, handleError, firstWhere, lastWhere, singleWhere, drain, asyncMap, asyncExpand, pipe, onData and onDone; any listen but `listen(null)` — with positive and negative controls; every card-path file pins its `.timeout(`, `onTimeout` and `sendCardCharge(` counts, and the Supabase implementation its exchange, `runCardCharge`, `.invoke(` and `unawaited(` counts (static); at most one deadline (none when refused before the SDK call) and no periodic timer captured in every failure row (transport, composition) |
| unexpected network access fails the tests | data_remote: `runWithoutNetwork` refuses `Socket.connect` / `startConnect` (IOOverrides) and every new HttpClient outside the allowed loopback port (HttpOverrides, `connectionFactory`), records every attempt and fails the test on any, with its own self-test (loopback); POS: every new HttpClient is refused and recorded, and tearDown fails on any (composition); the fixture replaces node's global fetch before loading the handler and reports every call (composition) |
| the card route cannot bypass the gate (delta review) | canonical, trailing-slash, prefixed and `:443` upper-case-host base URLs give one gated exchange; `/.`, `/a/..`, `/?a`, `#f` and `/?%FF` (an escape that is not UTF-8) base URLs give `notSent` / `handoffRefused` with zero requests (transport) and the server receives nothing (loopback); eight spellings of a direct invoke (the exact name, a trailing slash, a sub-path, upper case, a prefix, an encoded slash, the name in a query or a fragment) and four other origins or paths are refused (transport); a composed check that throws is `notSent` / `handoffRefused` (transport) |

Plus, from the design check (§8): a deadline during a gated token refresh, then the refresh released → `uncertain` /
`timeout` and zero card requests; a block or a `close()` during the gated refresh → `notSent`, zero requests; a
connection gated past the deadline → the server receives nothing; a plain SDK client through dart:io does follow a 303
(the sensitivity control of the redirect rows); the production bootstrap's `guardKitchenAcknowledgements: true` and
default inner client are pinned.

## 7. NOT VALIDATED and residuals

- Not validated: a physical Android device and the Android HTTP stack (the Dart tests run on the Windows VM); a web
  build (the refusal is a compile-time constant); the Deno / Supabase Edge runtime and the hosted gateway; any provider,
  terminal or card behaviour; Linux CI (no CI run exists for this branch).
- After the request's bytes are written, it may execute whatever the client does: an `uncertain` failure is honest,
  and 001F's `status` calls decide. The function can also outlast the 40 s through platform delays outside its own
  deadlines; that answer is `uncertain` too.
- The data_remote network guard intercepts `Socket.connect` / `Socket.startConnect` and HttpClient creation only; it
  does not intercept `RawSocket` or `SecureSocket` connections opened directly, `InternetAddress.lookup` or datagram
  sockets, and the POS composition test intercepts HttpClient creation only. No code under test uses those paths.
- **Resolved by the correction (§13.3):** the boundary's abort trigger uses `http.AbortableRequest`, which needs
  `package:http` 1.5.0 or later; `supabase` 2.13.3 allows `http ^1.2.2`, so in 001C only the lockfile (1.6.0)
  guaranteed it. `data_remote` now declares `http: ^1.5.0` (and, for its card transport test, `logging: ^1.3.0`), so
  the resolver refuses an older `http`; the POS app declares the `http` and `supabase` its SDK composition tests
  import. The lockfile is unchanged.
- The pre-handoff default (an error that is neither the gate's refusal, an `AuthException` nor the deadline) is
  `uncertain` / `transport` by construction; no known SDK path reaches it and no test does.
- The behaviour rows see a re-send through the timers it arms inside the call's Zone, a second deadline, or a request
  it sends within the settle or after the next token refresh. A re-send on a timer created outside that Zone (for
  example on `Zone.root`) is visible only to the static scan (mutant M54). The static scan reads source text and
  names only the constructs listed in §6 and the call-site counts; a re-send that used a construct it does not name
  and that the behaviour rows cannot observe would be seen by neither layer. Each layer covers forms the other cannot.
- The loopback 301 / 302 / 307 / 308 and 401 / 407 rows pin dart:io's own behaviour (it would not re-send those
  POSTs either); the boundary's redirect rule is proven by the 303 row and its control.

## 8. Design check before code (three read-only critics, 2026-10-29)

One small workflow of three fresh-context critics read the proposed design against the code and the locked SDK
sources before any code was committed: money-safety classification, SDK mechanics and test feasibility, scope and
conventions. They found 1 BLOCKER-level issue (raised by all three), 4 MAJOR, 15 MINOR and 9 NOTE items; every one is
reflected above or answered here.

| Finding | Disposition |
|---|---|
| A timed-out card call could still be sent later: `Future.timeout` cancels neither the SDK's token wait nor dart:io's connect (BLOCKER, all three) | §5.3: the Zone permit, ended synchronously at the deadline, so nothing can be handed off after it; the abort trigger for a connection still opening; tests in §6. The critics' `notSent` for a deadline before the handoff was adopted first and reverted at the delta review (§11): authorization §6 keeps every timeout `uncertain` |
| The guard was checked at entry only (MAJOR) | `isCurrent` threaded from the guard and the upgradable transport to the handoff |
| The planned timeout test could not detect the late send; the network guard missed HTTPS (MAJOR) | gated-refresh and gated-connect tests; the guard allows only the loopback port through `connectionFactory` and refuses every new HttpClient otherwise |
| Failure bodies invite misreading | dropped |
| `answered` accepted bodies the function never sends with 200 | the attempt echo and the non-200 tokens (the handler's 403 / 404 / 405 tokens added at the delta review); 001F still validates the closed shape |
| 40 s reasoning put the token refresh inside the margin and counted the upload twice | §5.5 restated: 31 + 2 + 7, the token step outside the margin |
| A web POS would get only false UNKNOWNs | `unsupportedPlatform` before any IO |
| Route matched by suffix; plain SDK calls passed through | exact endpoint, POST and bytes; refused outside an exchange. The delta review (§11) made the recognition itself fail-closed (any path segment naming the function), so a request that is not exactly the endpoint is refused rather than passed through |
| `rejected` read like a decline, `unknown` collided with the ledger state | `notApplied`, `uncertain` |
| Facts to correct (FINEST record, SDK importers, 4xx sources, non-retryable refresh, 503 sources) | §3 corrected; tests for the refused-refresh path |
| l10n, `apps/pos/test`, the boundary file and the stacked base not recorded | §1 |
| Re-asserting `providerProfile: null` in Dart ties 001C to the wiring ticket | kept on purpose: the instruction lists it; the ticket that wires the profile must change this test with it |

## 9. Results

At the code head `ec2cebac` (tree `85ef0e17`). The results commit that follows changes only this packet, so every
library, test and fixture blob below is the final head's; the final head re-runs every check, and the evidence folder
keeps its logs (named by head) beside these. Earlier heads passed the same checks: the delta review's fixes at
`7f350eee` (data_remote 157, the others as below; 48 of 50 mutants killed) and the closing check's at `ad271c76`
(data_remote 163; 60 of 62 killed).

| Check | Result |
|---|---|
| `dart format --output=none --set-exit-if-changed` (data_remote, auth_identity, the POS composition test) | no file changed |
| `dart analyze` packages/data_remote, packages/auth_identity, apps/pos | no issues |
| `dart test packages/data_remote` | 165 / 165 (base 40; + transport 91, loopback 19, static 15) |
| `dart test packages/auth_identity` | 148 / 148 (base 140; + guard 8) |
| `flutter test --no-pub` apps/pos, the nine affected files (the card composition test with 11, the guarded inbox composition, the kitchen ACK SDK, offline session, pairing gate, device-session recovery, payment-attempt recovery, durable outbox and inbox repository tests) | 151 / 151 |
| `flutter test --no-pub` apps/kds (pairing gate, session) | 38 / 38 |
| `flutter test --no-pub` apps/kiosk (device session round 3, live widgets) | 16 / 16 |
| `flutter test --no-pub` packages/feature_auth (credential safety, heartbeat scope, review rounds 1 and 2) | 58 / 58 |
| the `pos-card-charge` Node suite (the function is unchanged) | 187 / 187 on Node 22.14.0 and on Node 24.19.0 |
| focused mutations (`tools/mutate_001c.py`, outside Git) | 66 / 68 killed; every mutant compiles (0 analyzer errors; `node --check` for the four handler mutants), so no kill comes from a compile failure, and the log names the failing tests of each kill |

The mutation run applies one textual mutant at a time to an extracted copy of the head, runs the 001C test files that
should notice it, and restores the file; a control run passes before and after. Killed: every classification rule
(401, 408 / 425 / 429, 4xx, 5xx, the default, the boolean `ok`, the non-200 tokens, the attempt echo, the frozen body,
the 40 s value, the dedicated deadline), the pre-handoff classification (a refusal reported uncertain, the token reason
lost, the device-session reason lost, an unreachable refresh or a pre-handoff timeout reported `notSent`), the request
(content type, an added field), the event-stream cancel, the web refusal, every gate condition (route, redirects,
abort, second handoff, ended exchange, closed boundary, bytes, method, URL, the handoff check, outside an exchange),
the forwarding (the hold count, the caller check in both wrappers, the guard's entry and handoff checks), and the
delta-review mutants: the pre-review exact route recognition, last-segment-only, case-sensitive and substring
recognition (M39–M42); a 1 s, a zero-delay and a post-non-200 background re-send, each killed by the behaviour tests
alone (M43–M45); a typed-delay and a Zone-timer retry, each killed by the static test alone (M46, M47); and a missing
handler token (M48). And the closing-check mutants: a helper re-send only after a failure before the handoff, killed
by the behaviour tests alone (M49) and by the static test alone (M50); a replay after any failure before the handoff,
refusals included (M51, killed in the transport and composition tests); a timeout-driven re-send in the card body,
killed by each layer alone (M52 static, M53 behaviour); a re-send on a root-Zone timer that escapes the capture, which
only the static scan can see (M54); recognition in the path only, without decoding, and a card URL with a query or a
fragment handed off (M55–M57); a throwing handoff check escaping the gate (M58); and a non-200 handler reply split
across lines or built without `reply` (M59, M60). And the last-check mutants: the decoding fallback dropped (M61); a
handler response built with `Response.json` or a reply with a space before its parenthesis (M62, M63, static test
alone); a re-send waiting for the SDK's next token refresh after an unreachable one, killed by the behaviour tests
alone (M64) and by the static test alone (M66); and a re-send on a Zone timer armed when the token step fails, which
the back-off loop leaves pending (M65). Survived, both equivalent under Dart's event model: removing the
synchronous `exchange.end()` at
the deadline (M19) — the timer callback completes the call's future, whose `finally` then ends the exchange in a
microtask before any SDK continuation can run, because a token refresh or a connection resumes only from a later
event — and removing the `finally` end (M20) — the deadline still ends the exchange, a handed-off exchange can never
hand off again, and a call that failed before the handoff leaves no continuation that could reach the gate.

No test touched a network: every Dart test of 001C runs inside the denials of §6, and the composition fixture's
handler saw no global fetch.

## 10. Request-count and classification evidence

Every count is of requests to the card route; gotrue's own refresh requests (to `/auth/v1/token`) are the SDK's and
are counted apart. Every row of the transport test in which a card call fails or is refused also proves zero retry
by timer capture: after a real settle no timer the call armed is still pending, nothing periodic was armed, and it
armed exactly its one deadline (none when refused before the SDK call); the status, malformed, undecodable and post-handoff error rows also prove
exactly one request on the whole wire. The composition's failure rows prove the same through the boot guard.

| Situation | Card requests | Result | Test |
|---|---|---|---|
| a normal exchange | 1 | `CardChargeAnswered` | transport, loopback (wire), composition (online, degraded after upgrade) |
| each of 32 statuses (201 … 600; 402, 406, 407, 410, 412, 451 and 499 added by §13) | 1 each | the §5.4 row | transport |
| the pure classifier over 503 non-200 statuses (0, 99, 100–599 except 200, 600, 999), with a synthetic body and with twelve answer shapes (the seven non-200 tokens, a typed refusal of this attempt, an approved envelope, an HTML page, an empty body, none), with and without the attempt id | none (no transport) | 401 `unauthenticated`; 400 / 403 / 404 / 405 `notApplied`; every other `uncertain`, whatever the body | transport (§13) |
| 409 and 422 carrying the function's `invalid_request` token, and 407 with an HTML page | 1 each | `uncertain` / `httpStatus` | transport (§13) |
| each malformed 200 (20 shapes, the seven non-200 tokens among them) and undecodable body (3) | 1 each | `uncertain` / `malformedAnswer` | transport |
| each answered 200 (an envelope of this attempt, a typed refusal of it, a typed refusal without an attempt) | 1 each | `CardChargeAnswered`, unread | transport |
| reset, socket, TLS, any other error after the handoff | 1 each | `uncertain` / `transport` | transport; reset on the wire (loopback) |
| 301 / 302 / 303 / 307 / 308 on the wire | 1 each (no GET to `Location`) | `uncertain` / `httpStatus` | loopback; control without the boundary: 303 → POST + GET |
| 401 + `WWW-Authenticate`, 407 + `Proxy-Authenticate` on the wire | 1 each (no re-send) | `unauthenticated`, `uncertain` (§13) | loopback (pins) |
| the deadline after the handoff, then the late answer | 1 (no second) | `uncertain` / `timeout` | transport, loopback, composition (online and degraded-then-upgraded) |
| the deadline while the connection is still opening | 0 bytes reach the server | `uncertain` / `timeout` | loopback (gated connect) |
| the deadline during a held token refresh, then the refresh completes | 0 | `uncertain` / `timeout` | transport |
| `isCurrent` false / a guard block during a held token refresh | 0 | `notSent` / `deviceSessionUnverified` | transport, composition |
| a guard block right after the call started | 0 | `notSent` / `deviceSessionUnverified` | composition |
| the boundary closed during a held token refresh | 0 | `notSent` / `handoffRefused` | transport |
| a composed handoff check that throws | 0 | `notSent` / `handoffRefused` | transport |
| a revoked restore verdict, or a revoked heartbeat verdict, then the card call | 0 | `notSent` / `deviceSessionUnverified` | composition |
| a held call in hold mode, then the upgrade | 0 (never replayed) | `notSent` / `devicePrincipalPending` | transport, composition |
| a direct `functions.invoke` of the route outside the transport, in eight spellings | 0 | refused by the boundary | transport |
| other bytes, a query, another method, origin or path, a second handoff in one exchange | 1 handoff of 9 attempts | refused | transport (boundary unit) |
| canonical, trailing-slash, prefixed and `:443` upper-case-host base URLs | 1 each | `CardChargeAnswered` | transport |
| a base URL ending in `/.` or `/a/..`, or carrying a query (`/?a`, `/?%FF`) or a fragment (`#f`) | 0; the server receives nothing | `notSent` / `handoffRefused` | transport, loopback (with a canonical control: 1) |
| a plain SDK client (generic constructor); an unencodable body | 0 | `notSent` | transport |
| an expired session whose refresh is unreachable (its back-off waits run at once), then the connection returns and an ordinary call refreshes the session | 0, and 0 after the refresh | `uncertain` / `accessTokenUnavailable` | transport |
| an expired session whose refresh is refused (gotrue signs out) | 1, Bearer = the public key | `unauthenticated` (401) | transport |
| the real handler: a start (flag off) / a non-integer amount / a status with no database | 1 each | answered `card_payments_disabled` / `notApplied` 400 / `uncertain` 503 | composition (real handler; injected fetches: none / none / exactly `…/rest/v1/rpc/card_attempt_context`; global fetches: none) |

## 11. Review

One fresh-context Claude delta review (one workflow, 2026-10-29) of `cf1ffacf..45e55bc9`: three read-only lenses
(tests, money safety, scope and conventions), then one adversarial verifier for each of the six highest findings. Every
agent reported that it wrote nothing to the worktree or the evidence folder; `git status` stayed empty and the evidence
folder gained only this run's own mutation log. Reproductions ran in isolated scratch copies outside the worktree. No
Codex review was requested.

15 findings: 2 MAJOR, 6 MINOR, 7 NOTE. All six verified findings were confirmed, none refuted; the verifier of the
route finding downgraded it from MAJOR to MINOR, because no realistic or shipped base URL triggers it. Every finding
is fixed in `7f350eee` (tree `8fd93d3b`) — completed in `4010d4e0`, `ad271c76` and `ec2cebac` where the closing and
last checks below found gaps — or answered below.

| Finding | Verdict | Disposition |
|---|---|---|
| A delayed background re-send survived every test; the static pattern missed `Future<void>.delayed`, `createTimer` and `Retry` (tests, MAJOR) | confirmed, MAJOR | the rows after the handoff prove zero retry by timer capture (`7f350eee`); the closing check found the rows before the handoff and the refusals uncovered, and `4010d4e0`, `ad271c76` and `ec2cebac` extend the proof to every row in which a card call fails or is refused (§10); the pattern is widened, has positive and negative controls and reads the card-path files whole; mutants M43–M47, M49–M54 and M64–M66 (§9) |
| Card-route recognition failed open for a base URL with dot segments: the request bypassed the gate and a sent request could be reported `notSent` (money safety, MAJOR) | confirmed, MINOR | recognition by any path segment naming the function, any letter case, with the exact endpoint still required (§5.3) — since `4010d4e0` also a name in the query or fragment, and no card URL with a query or fragment is handed off; base-URL, spelling, boundary-unit and loopback rows; mutants M39–M42 and M55–M57 |
| `cardChargeNon200Errors` lacked the handler's 403 / 404 / 405 tokens (money safety, MINOR; with the scope NOTE on the same set) | confirmed, MINOR | added; the static test derives the set from `statusOf` and the handler's explicit replies, and the transport test writes the seven out; mutant M48 |
| `notSent` for a timeout or lost connection before the handoff departs from authorization §6 (scope, MINOR) | confirmed, MINOR | §6 followed literally: once the SDK call has started, only the gate's refusal is `notSent` (§1, §5.4); mutants M16b, M16c |
| A false caller `isCurrent` is labelled `deviceSessionUnverified`, with no matrix row (scope, MINOR) | confirmed, MINOR | the reason's doc and §5.4 name the composed check (the guard's block and a caller's own check; the upgradable identity check is defensive and cannot fail); a check that throws is `handoffRefused`, pinned by a test (`4010d4e0`, mutant M58); the POS compositions pass no caller check; the name is kept |
| §6 overstated the network guard and the guard test's authorization coverage (tests, MINOR); two rows claimed coverage the tests lacked, "heartbeat" where a restore verdict was used (scope, MINOR); the isolation claims did not match the guard code (scope, MINOR) | confirmed (tests); not verified (scope, beyond the cap) | §6 and §7 corrected; a heartbeat-verdict composition test added; the POS denial now records attempts and fails in tearDown |
| The fixture was isolated by injection only, and the status-row fetch assertion was vacuous on an empty list (tests, NOTE) | not verified | the fixture replaces node's global fetch before loading the handler and reports it; the status run asserts its exact fetch list |
| The loopback 301 / 302 / 307 / 308 and 401 / 407 rows are insensitive by construction (tests, NOTE) | not verified | labelled as pins; the 303 row and its control are the proof (§7) |
| `notApplied` / `unauthenticated` docs said "refused before the function acted / changed nothing" (scope, NOTE) | not verified | "refused with no ledger effect of this request" |
| The timeout derivation dropped its source's caveats and assumed a streamed body (scope, NOTE) | not verified | §5.5 and the constant's doc name request buffering and co-scheduled requests in the allowance, and **Q-039** for the CPU accounting |
| The library needs `package:http` 1.5.0 or later, guaranteed only by the lockfile (scope, NOTE) | not verified | §7, a separately reported need; no manifest or lockfile change |
| §2 gave a stale branch's tip, not the commit that touched the guard file (scope, NOTE) | not verified | §2 corrected (`3c485e9e`; `271fbc7e`) |

Confirmed correct by the reviewers, among others: the scope (15 paths, all authorized; nothing under `supabase/`,
migrations, CI, manifests, l10n or the apps' `lib`); `providerProfile: null` and the candidate's single importer; no
abstraction beyond the one seam; the timeout arithmetic against `constants.mjs` and the 001E packet; the 15 s timeout
untouched; the §2 anchors and §3 line references; the SDK facts against the locked sources; the Edge surface; the
classification against the code; `classifyTransportFailure`; the recorded deviations; and every authorization §7 test.

### Closing check of the dispositions

After the fixes, a second small workflow checked the dispositions from a fresh context — the closing step of the same
review, not a new review of the ticket: three read-only checkers (money safety of the fixes, test strength of the
fixes, documentation and scope), then a refute-first verifier for each of the three MINOR-or-above findings. Every
agent reported no write to the worktree or the evidence folder, and a hash manifest of both, taken before the run and
compared after it, shows only this ticket's own changes. Reproductions ran in scratch copies.

It confirmed 13 of the 15 dispositions in full and two in part (tests F1 and scope F002, below), and found 11 items:
1 MAJOR, 2 MINOR, 8 NOTE. The three verified items were all confirmed. Each is fixed in `4010d4e0` (tree `0b09dd5f`)
and `ad271c76` (tree `d8bc7762`, the composition's real-handler failure rows) or in this packet and the evidence
documents:

| Finding | Verdict | Disposition |
|---|---|---|
| Zero retry was still unproven after a failure before the handoff (the held-refresh deadline, the unreachable refresh, the refusals) and for a replay of a refused request; the static scan did not reach helpers outside the card methods (tests, MAJOR) | confirmed, MAJOR | every failure row of the transport and composition tests proves after a settle that no timer is pending, nothing periodic was armed and exactly its deadlines were armed (completed in `ec2cebac` with the direct-invoke and boundary unit rows); the unreachable refresh runs its back-off at once, then the connection returns and nothing is sent (made to use the returned connection in `ec2cebac`); the static scan reads the five card-path files whole against pinned existing matches; mutants M49–M54 |
| The documents claimed "every failure row" while 13 rows were not captured (docs, MINOR) | confirmed, MINOR | the claim is now true (above) and stated with its scope in §6, §10, §11 and the evidence documents |
| The widened pattern still missed a typed `then`, `Future.doWhile` / `forEach`, stream listeners, a timeout-driven re-send and a recursive call (tests, MINOR) | confirmed, MINOR | the pattern covers typed `then` / `catchError` / `whenComplete`, `doWhile` / `forEach` and any listener but `listen(null)`, with positive and negative controls; call-site counts pin `sendCardCharge(`, the exchange, `runCardCharge(`, `.invoke(`, `.timeout(` and `onTimeout`; mutants M52, M54 |
| The token-union test saw a new non-200 reply only on one line, and missed a direct `jsonResponse` (tests, NOTE) | not verified | reply calls are matched across lines; the handler's single `jsonResponse` call and the absence of `new Response` are pinned; mutants M59, M60 |
| A base URL with a query or a fragment took the SDK's card request out of path recognition, so it passed the gate ungated — no money effect: the handler refuses it with 404, and such a base cannot sign in (money safety, NOTE) | not verified | the boundary recognizes the name in the decoded path, query or fragment and refuses a card URL with a query or a fragment, so such a base is refused before any IO (transport, loopback); mutants M55–M57 |
| A composed handoff check that throws becomes `handoffRefused`, which §5.4 and the docs did not name (money safety and docs, NOTE) | not verified | named in §5.3, §5.4 and the reason's doc; pinned by a test; mutant M58 |
| `runCardCharge`'s doc still said "device-session check"; §5.4 and the disposition named an upgradable replacement that cannot happen (money safety and docs, NOTE) | not verified | the doc names the composed check; the identity check is described as defensive |
| `httpStatus` was documented for non-200 answers only, and the verdict tests were credited to the handoff check (docs, NOTE) | not verified | the class doc and the interface map say "any non-200, or a malformed 200"; the verdict tests are credited to the entry refusal |
| DESIGN_CHECK.md did not mark HTTP-01 as revised, and two evidence documents dropped "once the SDK call has started" (docs, NOTE ×2) | not verified | corrected |

### Last check of the closing-check fixes

A last small workflow checked those fixes the same way (two read-only checkers — code and tests; documentation,
counts and scope — and a refute-first verifier for each of the two MINOR items). Every agent reported no write, and
the hash manifest of the worktree and the evidence folder again shows only this ticket's own changes. It confirmed
all 11 closing-check items as fixed, with residuals, and found 10 items: 2 MINOR (both confirmed), 8 NOTE. Each is
fixed in `ec2cebac` (tree `85ef0e17`) or in this packet and the evidence documents. The review loop stops here: the
last items are wording and further test hardening, each closed with a killed mutant where code or tests changed.

| Finding | Verdict | Disposition |
|---|---|---|
| In the unreachable-refresh row the "connection returns" step never made the SDK use the connection, and the back-off loop also ran a re-send timer armed when the call failed (code and tests, MINOR) | confirmed, MINOR | the loop runs back-off waits only while the call is pending; once the connection returns an ordinary call makes the SDK refresh the session, and the row then proves nothing was sent; mutants M64 (a re-send waiting for the next token refresh) and M65 (a Zone timer armed at the failure) |
| The static scan's coverage was overstated: `onError`, Stream `forEach` / `drain`, a `.timeout` re-send outside the Supabase file were not named, and the card path has pinned loops (docs, MINOR; with the code-and-tests NOTE on the same pattern) | confirmed, MINOR | the scan also names onError, forEach, handleError, firstWhere, lastWhere, singleWhere, drain, asyncMap, asyncExpand, pipe, onData, onDone, `Future.wait` and `Future.any`, with controls; every card-path file pins its `.timeout(`, `onTimeout` and `sendCardCharge(` counts; §6, §7, the test's doc and the interface map name exactly what is matched; mutant M66 |
| No test reached the decoding fallback: a query base with an escape that is not UTF-8 could pass ungated with the fallback removed (code and tests, NOTE) | not verified | a `/?%FF` base URL row (transport, loopback); mutant M61 |
| The handler check missed `Response.json` and a call with a space before its parenthesis (code and tests, NOTE) | not verified | whitespace allowed before a call's parenthesis; `Response.json` / `error` / `redirect` pinned to none; mutants M62, M63 |
| The direct-invoke spellings and the boundary unit row had no timer capture (docs, NOTE) | not verified | both run in the capturing Zone and prove no pending work |
| "One deadline in every failure row" (§6) and the `ad271c76` message's "exactly one deadline" ignored the rows refused before the SDK call; the spellings' parenthesis omitted the exact name (docs, NOTE) | not verified | "at most one (none when refused before the SDK call)"; the `ec2cebac` message records the correction; the exact name listed |
| `httpStatus` "any non-200, or a malformed 200" was false for an answer whose body could not be decoded; "failed" for the composed check read as including a throw; `_capture`'s doc ignored zero-duration timers (docs, NOTE) | not verified | "no status when the body could not be decoded"; "returned false" (a throw is `handoffRefused`); "every non-zero timer" |
| DESIGN_CHECK.md did not mark TEST-02 as revised (docs, NOTE) | not verified | marked; six revised dispositions |
| §11 credited the closing-check fixes to `4010d4e0` alone (docs, NOTE) | not verified | `ad271c76` named above |

## 12. Readiness and remaining gates

**LOCAL_001C_CARD_TRANSPORT_READY_PROFILE_AND_VENDOR_GATES_HELD** — the capability is implemented, forwarded by both POS
boot compositions and tested with fake and loopback HTTP only. It is not wired to any flow (001F), and nothing is
runtime-ready.

- **Profile and vendor gates held:** `index.ts` keeps `providerProfile: null`; the Z-Credit candidate is imported only
  by its own test; no provider host, credential, terminal reference or card value is in Dart. **Q-047** and **Q-049**
  (hard owner gates), E2-B, **Q-048**, **Q-050** and **Q-052** stay open.
- **Before the transport carries a real exchange:** 001F (the attempt journal and persist-before-send, single-flight
  polling with back-off, the outcome UX and its ar / he / en strings, the lab toggle, `attempt_not_found` treated as
  inconclusive while a handed-off `start` may still be in flight); 001H; [DEPLOYMENT](DEPLOYMENT.md) §18; the 001D
  merge (S14 C) and the merges of 001E and its follow-ups that this branch stacks on.
- **Open documentation item:** align the checklist row and the pilot §7 allowlist with this authorization (no l10n in
  001C) — a separately approved docs change.
- **Separately reported need — resolved** by the correction: `data_remote` declares `http: ^1.5.0` (§13.3).
- **Not validated:** §7.
- Publication — any push, PR or merge of this branch and of the branches it stacks on — needs its own process
  decision.
- **Corrected** by §13 (the closed status policy and the dependency declarations), which records its own readiness.

## 13. Transport corrections (`BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C-TRANSPORT-CORRECTIONS-001`)

### 13.1 Authorization and boundary

A separate Work ID on its own local branch,
`fix/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001C-TRANSPORT-CORRECTIONS-001-status-policy-and-deps`, whose parent is this
packet's reviewed head `71bfef5b` (tree `4a341b77`); the 001C branch and its accepted package are unchanged. The
command room's instruction (2026-10-30) asks for the closed HTTP status policy of §13.2, the four direct dependency
declarations of §13.3, a bounded resolution with the repository's pinned toolchain (a lockfile change committed only
if the resolver makes one, and reported exactly), and focused validation and review. It preserves the 40 s deadline,
the pre-handoff `uncertain`, one HTTP handoff at most, zero automatic retry, the exact request bytes,
`providerProfile: null`, every earlier branch and its evidence, and #370 / #371. No push, PR, merge, hosted action,
deployment, provider request, credential, terminal or card.

- **Recorded deviation (none silent):** step 6 of the instruction asks for "the exact focused validation and review
  requested in the command-room correction prompt"; that prompt never reached this work (no session record, evidence
  folder or download names this Work ID before the instruction itself). The validation and the review were therefore
  chosen here: the accepted 001C check set re-run at the head, plus the one other POS test that imports `package:http`
  and `package:supabase` and CI's Vercel filter test (it parses both manifests); the bounded-resolution logs; the
  status matrix before and after; the dependency table; the 001C mutation harness with the closed-policy mutants; and
  one fresh-context Claude delta review with refute-first verifiers (no Codex review). The correction's evidence note
  `decision/NOTE_REFERENCED_CORRECTION_PROMPT.md` records the first choice and its update after the review (CI's
  Vercel filter test, the review's mutants N15–N17, the reproduction from clean copies); anything else the unseen
  prompt asked for is not done.

### 13.2 The closed status policy

| HTTP status (non-200) | Before (`71bfef5b`) | After |
|---|---|---|
| 401 | `unauthenticated` | `unauthenticated` |
| 400, 403, 404, 405 | `notApplied` | `notApplied` |
| 402, 406, 407, 409–424, 426–428, 430–499 (92 statuses; 407, 409, 413, 415 and 422 among them) | `notApplied` | `uncertain` |
| 408, 425, 429 | `uncertain` | `uncertain` |
| any 1xx, non-200 2xx, 3xx or 5xx, and any status outside 100–599 | `uncertain` | `uncertain` |

A 200 is classified by the answer's shape exactly as before (§5.4); only `classifyCardChargeAnswer`'s status switch,
its comment and two kind docs changed. A decoded body never changes a non-200 status's kind; a body that cannot be
decoded makes any answer `uncertain` / `malformedAnswer`, with no status (§5.4). The four `notApplied` statuses are
the ones the function answers only before any ledger write: the handler's boundary answers `origin_not_allowed`,
`not_found` and `method_not_allowed` with 403, 404 and 405 before any database call, and `statusOf` answers
`invalid_request` with 400, which the handler and the ledger RPCs return before their first write. The function's
other refusal status, 503 (`provider_unavailable` / `unavailable`), can follow a committed claim and stays
`uncertain`. Its 401 (`invalid_session`) writes no ledger, audit or private-event row (API_CONTRACT §4.55.2), and its
400 comes before the refusing RPC's first write (§4.55.4 states it for `start`), though the context proof may already
have renewed the device session for either, so `unauthenticated` and `notApplied` mean "no ledger effect", never
"nothing reached the server". The gateway does not verify JWTs for this function (`verify_jwt = false` in
`supabase/config.toml`), so a 401 comes from the handler; a platform 404 for an undeployed function would also mean
that the function did not run (the hosted gateway is not validated, §7). A 4xx the function never sends — a proxy's
407, an intermediary's 409, 413, 415 or 422 — proves nothing about whether this request had a ledger effect, so it is
UNCONFIRMED, like a timeout.

### 13.3 Dependency declarations and the lockfile

| Package | Dependency | Before | After | Resolved version |
|---|---|---|---|---|
| `restoflow_data_remote` | `http` | transitive only | `dependencies: ^1.5.0` | 1.6.0 (unchanged) |
| `restoflow_data_remote` | `logging` | transitive only | `dev_dependencies: ^1.3.0` | 1.3.0 (unchanged) |
| `restoflow_pos` | `http` | transitive only | `dev_dependencies: ^1.5.0` | 1.6.0 (unchanged) |
| `restoflow_pos` | `supabase` | transitive only | `dev_dependencies: '>=2.0.0 <3.0.0'` | 2.13.3 (unchanged) |

`data_remote`'s HTTP boundary imports `package:http`, and its abort trigger needs 1.5.0 or later (§7); its card
transport test imports `package:logging`; the POS app's SDK composition tests (the card charge, the kitchen ACK, the
online-order inbox and the background alerts) import `package:http` and `package:supabase`. The bounded resolution
ran with Flutter 3.44.2 stable and Dart 3.12.2 (CI's pin): `flutter pub get --offline` (the local pub cache; the
locked versions kept; no upgrade requested), then `flutter pub get --offline --enforce-lockfile`. Both pass, and
`pubspec.lock` is byte-identical (blob `d0aba4d0`): the locked versions already satisfy the new constraints, no
locked version changed (204 locked packages; `flutter pub deps --json` lists 230, counting the 26 workspace
packages), and the lockfile's `dependency` fields are relative to the workspace root, which declares only `melos`. No
lockfile change is committed.

### 13.4 Files

`packages/data_remote/lib/src/card_charge_transport.dart` (the status switch, its comment and the `notApplied` /
`uncertain` docs); `packages/data_remote/test/card_charge_transport_test.dart` (status rows 402, 406, 407, 410, 412,
451 and 499 added — 32 rows —, the 409 / 413 / 415 / 422 rows now `uncertain`, a sweep of the pure classifier over
503 non-200 statuses with literal expected sets, and — from the review — the same sweep over twelve answer shapes and
three wire rows whose body claims a refusal); `packages/data_remote/test/card_charge_loopback_test.dart` (the 407
challenge is `uncertain`); `packages/data_remote/pubspec.yaml`; `apps/pos/pubspec.yaml`; and this packet (the header,
§1, §5.4, §6, §7, §10, §12 and this section). Every other file is unchanged, `pubspec.lock` included.

### 13.5 Validation

At the code head `c598bb4a` (tree `4049ec82`), run at `1288a68c`, whose code, tests and manifests are `c598bb4a`'s
(the bounded resolution's head log is `4afbeceb`'s: the same manifests and lockfile). The commits after it change only
this packet, so every library, test and manifest blob is the final head's. The final head re-runs every check, the
bounded resolution and the reproduction; the final mutation log is at `e2305b43` (the same code); the correction's
evidence folder keeps the logs, named by head. Fake and loopback HTTP only.

| Check | Result |
|---|---|
| `dart format` (`data_remote`, `auth_identity` and the POS card composition test) | 77 files, 0 changed |
| `dart analyze` (`data_remote`, `auth_identity`, `apps/pos`) | no issues |
| `dart test packages/data_remote` | 177 / 177 (165 at the parent; + 7 status rows, the closed-policy sweep, the body grid and 3 body rows) |
| `dart test packages/auth_identity` | 148 / 148 |
| POS: 001C's nine files and `background_order_alert_registration_uncertainty_test.dart` | 152 / 152 |
| KDS / Kiosk / feature_auth guard tests | 38 / 16 / 58 |
| the `pos-card-charge` Node suite | 187 / 187 on Node 22.14.0 and on Node 24.19.0 |
| CI's Vercel filter test (`tools/vercel/ignore-build.test.mjs`, which parses every workspace manifest) | 170 pass, 0 fail, 2 skipped on Windows (POSIX filename cases — newline / tab and raw non-UTF-8 bytes — that run only on a POSIX checkout such as CI) |
| the bounded resolution at the parent, with the new manifests and at the head | `flutter pub get --offline` and `--enforce-lockfile` exit 0 each time; `pubspec.lock` blob `d0aba4d0` throughout |
| the real classifier's status matrix | before: 96 `notApplied`, 1 `unauthenticated`, 406 `uncertain`; after: 4, 1 and 498 |
| clean copies of the parent and the head | both `flutter pub deps --json` graphs and both matrices reproduce exactly |
| focused mutations (`tools/mutate_tc001.py`, outside Git) | 79 / 81 killed; every mutant compiles; the survivors M19 / M20 are 001C's two equivalent mutants |

The mutation set is 001C's with its four 4xx-range mutants replaced by N01–N14 — a status added to the closed set
(407, 409, 413, 415, 422, 418, 503) or dropped from it (400, 403, 404, 405), the 001C policy restored, a range, 403 as
`unauthenticated` — and the review's N15–N17, a 4xx trusted by a body carrying a non-200 token, an attempt id or
text. All seventeen, M01 (401 as `notApplied`) and M06 (the default as `notApplied`) are killed by the tests that
should notice; before the review, `c4530b8a` killed 76 of 78. Every test of each check run is listed by name (the
`TESTS_<suite>_<head>` logs and the TAP logs), and the worktree had no change before or after the checks. The mutation
logs of `c4530b8a` and `1288a68c` name at most three failing tests per suite, cut at 140 characters; the final one
names every failing test in full.

### 13.6 Review

One fresh-context Claude delta review of `71bfef5b..4afbeceb` (no Codex review): three lenses — money safety and the
closed policy; tests and evidence; scope, dependencies and packet accuracy — and one refute-first verifier per
MINOR-or-above finding. All five MINOR findings were confirmed and fixed: the docs say why the four statuses are
definitive, and the switch comment and §13.2 name the function's 503 (TC001-MONEY-01); the body grid, the three body
rows and N15–N17 prove that no decoded body changes a non-200 kind (TC-T1); §13.5–§13.7 record the results and the
readiness (F1); §13.2 no longer claims a gateway 401 (F2); §13.1 records the missing correction prompt as a deviation
(F3). Of the eight notes, seven were recorded or acted on (the 401 caveat, 001F's mapping, two counts, CI's Vercel
filter test, the reproduction from clean copies, per-test logs) and one was kept by choice: this record lives in the
001C packet (F6). A closing check of those dispositions, with refute-first verifiers, found ten resolved, F1 pending
by design and two partly done (both completed since). It raised five more items, all handled: two confirmed MINOR
findings — "the body never changes a status's kind" holds for a decoded body only (§5.4, §13.2), and the evidence note
named only the first validation choice; one MINOR refuted to a NOTE whose remainder is fixed (a tool now writes the
after-matrix log); and two NOTEs (an earlier record said both reworded texts name the 503; the mutation log cut
failing test names, so the final one names them in full). A last read-only check of §13.5–§13.7 and the evidence
fixes found four wording errors, corrected in the commit after `e2305b43`, and six notes. Hash manifests of the
worktree and the evidence folder before and after each run show that no review agent wrote anything. The dispositions
are in the evidence folder's `review/REVIEW_DISPOSITIONS.md`.

### 13.7 Readiness and remaining gates

**LOCAL_001C_CORRECTED_READY_FOR_COMMAND_ROOM_REVIEW_PROFILE_GATES_HELD** — the closed status policy and the four
dependency declarations are implemented and validated with fake and loopback HTTP only; the lockfile is unchanged; the
transport is still wired to no flow.

- **Profile and vendor gates held:** `index.ts` keeps `providerProfile: null`; **Q-047** and **Q-049** (hard owner
  gates), E2-B, **Q-048**, **Q-050** and **Q-052** stay open.
- **For 001F:** map `CardChargeFailureKind` directly (`notSent` / `notApplied` → not applied, `unauthenticated` → auth
  required, `uncertain` → UNCONFIRMED), never feed `httpStatus` to `classifyTransportFailure`, and pin it with a test
  that a card `uncertain` failure carrying 409 or 422 never becomes not applied.
- **Integration:** this branch stacks on 001C, the profile candidate, D-064, W1, G1, 001E and #370. On 2026-10-30
  `origin/main`'s drift since the stack's merge base `d2079820` touches no file this correction changes; it shares
  seven l10n files (the three ARB files and the four generated localizations) with #370's commit `40147318`, which the
  stack's own integration must resolve. Any push, PR or merge needs its own process decision.
- **Not validated:** §7.
