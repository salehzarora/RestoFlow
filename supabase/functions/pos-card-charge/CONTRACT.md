# Card-present provider adapter — `pos-card-charge`

`POST /functions/v1/pos-card-charge` implements [API_CONTRACT.md §4.55](../../../docs/API_CONTRACT.md)
for the native Android POS (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E). The execution packet
[docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md](../../../docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md)
holds the source anchor, constants, test lanes and gates. This source authorizes no deployment,
secret, provider request, terminal operation or card use.

## Boundary and authority

POST only, on the function path, no query string, no `Origin` (native only, no CORS), a Bearer JWT
of three segments, `application/json`, at most 16 KiB of strict JSON, and the exact key set of the
action (`start`, `status`, `release`, `free_order`). The JWT is never decoded here: PostgREST
verifies it when the read-only context proof `card_attempt_context` runs with that header and the
anon key. Only a successful proof opens the service-role client in `lib/ledger.mjs`, which appends
that proof's `caller_auth_user_id` to every session-proving call of the same request. Each call is
one PostgREST RPC (one READ COMMITTED transaction). `card_attempt_finish` is scope-bound to the row
id and facts the same request's claim or adapter read returned.

## Actions

- `start`: master flag, configuration and wire profile checks before any database read; the proof;
  the claim; exactly one provider commit only for `claim_created = true` under a 100 s budget,
  after the claim's scope, stored keys and the attempt's own frozen references are checked; the
  answer within a 3 s window (`sent` while the terminal interaction continues under
  `EdgeRuntime.waitUntil`, which is not a durable queue and lasts at most the worker's remaining
  lifetime). Timeout, network loss, a duplicate refusal or any unreadable reply is UNKNOWN; nothing
  is retried.
- `status`: the proof; the adapter read with the configuration maps, checked against the proof's
  organization, restaurant and (for a cashier) device; for `sent` / `unknown` / `released` without
  a resolution, one lookup by the stored key under the attempt's own frozen references. At most 90
  automatic (`source = 'auto'`) polls per attempt for a cashier; lookups of one attempt at least
  3 s apart for every source and role (database clock), inside that interval the stored envelope
  with no provider call and no write; an absent or unreadable stamp answers `unavailable`, and a stamp
  ahead of the database clock never suppresses a call. An attempt with a resolution answers its
  envelope; otherwise an approved attempt's `recording_refused` report goes to
  `card_attempt_mark_recording_result` and needs no configuration.
- `release`: advisory, only `sent` / `unknown` without a resolution: adapter read (same scope
  checks), at most one release request per 3 s (database clock, from `release_requested_at`, which the
  mark writes before the provider call; an absent or unreadable stamp answers `unavailable` and a stamp
  ahead of the clock never suppresses), the release mark, one provider release, the finish (which carries
  only the reply's dropped-field tokens, never a provider value). A release
  inside that interval answers the stored envelope with no mark and no provider call: it is not a
  confirmation (only state `released` confirms one), and a retry after the interval marks again.
- The poll cap and both intervals are best effort: overlapping requests can each pass them, and a
  failed lookup finish stamps and counts nothing (a release's mark is written before its provider
  call, so a failed release finish still starts its interval). 001F polls one request at a time per
  attempt and backs off on 503.
- `free_order`: the role is proven before any attempt lookup; a manager+ proof makes one
  `card_attempt_free_order` call.

## Money and replies

Amounts never pass through a JavaScript `Number`: integer tokens stay text, and outbound money stays
the canonical `X.XX` lexeme (one to nine integer digits, exactly two fraction digits), built with
`BigInt` division and modulo and sent as an unquoted number token. Inbound provider money, the
amount and the tip (DECISION D-064), must be a raw JSON number token, read as its token text (a
missing key, JSON null or a blank string stays absent): it accepts zero, one or two fraction digits
(`^(0|[1-9][0-9]{0,8})(\.[0-9]{1,2})?$`) and is right-padded to the canonical `X.XX` (`12` is read
as `12.00`, `12.3` as `12.30`; never rounded). JSON strings (even `"12.34"`), signs, exponent
notation, more than two decimals and values over the nine-digit bound are refused (the format
rule), and only the canonical `X.XX` reaches `card_attempt_finish`. Only ILS (two decimals) can be
encoded. A reply is read only at the wire profile's allowlisted names; a field
failing the shared text policy (or, in a structured field, the stricter truncated-card shape check)
is dropped before the finish and a failing essential field fails the outcome closed. For a 2xx reply
that is a readable JSON object, only the `{field, rule}` tokens of each failing allowlisted field (its
text-policy, shape or format rule) reach `card_attempt_finish`, as `dropped_fields` (DECISION D-062),
which writes the private dropped-field event and applies the same essential and tip flags (nothing is
recorded for a resolved, final or out-of-scope attempt, nor for a commit reply that arrives after the row
left `sent`). TEST attempts never read the card or provider-reference fields. A lookup whose reply is
not a readable 2xx JSON object (a transport failure included) is `failed` (no provider fact) before
any field is read. In a readable reply, a present status that is unreadable, or readable but in none
of the profile's status lists after the normalization (NFKC and the Space_Separator trim; no case is
folded), is the `out_of_contract` anomaly first, before any return code or approval type is read: no
listed not-found / pending return code and no declined or approved approval type overrides it
(DECISION D-063). A status is absent only when its key is missing, its value is JSON null or it is a
string that is empty or holds only Space_Separators; `0`, `"0"`, `"null"`, `"-"` and every other
present value are statuses, never absent. Otherwise a lookup reply is classified `not_found` /
`pending` when it carries a listed not-found / pending status or - with no status - a listed not-found
/ pending return code, whatever else it carries (a listed status always decides); SQL then leaves the
attempt unchanged, except that a `sent` row past its start deadline moves to `unknown`, and stamps the
lookup. Otherwise a void, refund, partial-refund or pre-authorization status is classified as its own
anomaly (`out_of_contract` when an essential field failed), and an approved status as `approved`
unless the approval type declines it or an essential field failed (the `out_of_contract` anomaly);
SQL approves that classification only when the echoed status, amount and currency are present and
neither the error flag nor the phone authorization is true (otherwise `out_of_contract`), the amount
equals the attempt's with no tip or a zero tip (otherwise `amount_mismatch`) and the currency is the
attempt's (otherwise `currency_mismatch`). Otherwise - with no status - a declined approval type with
no failing essential field (the engine's eight, the tip included) declines (the vendor has no decline
status), and a declined type with a failing essential field, an approved type, a readable amount or
an unreadable approval type, amount, tip or return code are the `out_of_contract` anomaly; any other
reply is `failed` (no provider fact). The engine's `classifyLookup` holds the full precedence
(API_CONTRACT section 4.55.5).

## Gates

The entrypoint supplies the reviewed provider candidate: `index.ts` passes `ZCREDIT_PROFILE_CANDIDATE`
from `lib/provider/zcredit_profile.mjs` (version `zcredit-ws-pinpad-candidate-1`; wired by
BIZBOT-PAYMENTS-ZCREDIT-PILOT-001H-PROFILE-WIRING-001, gate W1 of packet §6). The handler still takes a
profile only as a constructor option (none by default), and no configuration selects one. That module is
kept byte-identical, so its source, data, recovery and credential-member pins hold; its header comment
("Only the tests import it", "index.ts keeps providerProfile: null") is historical - it describes the
candidate as reviewed before the wiring and is not the runtime import invariant. With the master flag
absent, `start` refuses before a database call. A start that reaches the claim also needs the existing
revision and binding gates. Recovery operations (`status`, `release`) retain their existing behavior; no
provider request from a missing attempt is possible through those paths. The no-provider-request
conclusion for a disabled deployment therefore depends on the complete verified posture, including the
absence of relevant recoverable attempts, not on the OFF flag alone: turning the flag OFF stops new
starts and cancels no request already sent. A refusal does not validate the installed configuration,
the credentials, the PIN-pad mapping or the profile against the provider; that wiring is local source
until a separately approved deployment, and provider acceptance is observed only in a separately
authorized TEST session. A field the adapter drops from a
2xx JSON-object reply reaches the SQL-written `security.card_provider_field_dropped` event as
`dropped_fields` tokens, recorded unless the attempt is resolved, final or out of scope or a commit reply
arrives after the row left `sent` (gap G1, closed locally by DECISION D-062:
docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_DROP_EVIDENCE_001_EXECUTION.md).
Q-047 / Q-049 and the owner gates of DEPLOYMENT §18 still govern every real provider action (DECISION
D-065 closed Q-047 and closed Q-049 for the phase-1 TEST only; E2-B stays open).

## Local proof

`node --test supabase/functions/pos-card-charge/test/*.test.mjs` — synthetic data, a scripted fake
provider and a scripted fake PostgREST; the suite refuses any real network connection. It proves
request wiring and provider-call counts, not provider acceptance, hosted isolation or the edge
runtime itself.
