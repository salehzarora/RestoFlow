# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F — execution packet: the POS card journal, UI and recovery (local, fake Edge only)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F` (a ticket of the umbrella
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md); its §4 row "POS Payment Lab" and the
[IMPLEMENTATION_CHECKLIST](IMPLEMENTATION_CHECKLIST.md) row of the same Work ID). Controlling contract:
[API_CONTRACT](API_CONTRACT.md) §4.55 with **D-051** .. **D-064**; the POS transport is the one of
[the 001C packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001C_EXECUTION.md) as corrected by its §13. This packet records no
**DECISION**, adds no **OPEN QUESTION** and allocates no ID.

This packet was written and committed before any executable change (authorization §1). §5 – §11 were then brought in
line with the corrections of the review rounds (§13); §14 records the results.

**Corrected 2026-10-31** by
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-JOURNAL-RECOVERY-CORRECTIONS-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001F_JOURNAL_RECOVERY_CORRECTIONS_001_EXECUTION.md)
(a command-room source review of this packet's head `d7ce9990`): an unresolved TEST attempt stays recoverable whatever
the lab toggle (within the limits of that packet's §4.4), the 200-record bound is an admission bound, and an envelope
holding duplicate identities is quarantined. The statements of §5.2, §5.3, §5.4, §7.1 – §7.3, §9.3 and §14.4 item 4
that it changes carry a dated note below; that packet holds the corrected rules.

## 1. Authorization and boundary

- Command-room authorization of 2026-10-30, "LOCAL POS CARD JOURNAL, UI AND RECOVERY — FAKE EDGE ONLY". It accepts
  the 001C correction locally at `148df092f08e71e39abfcf493835a1d852cfa9f7` (tree
  `e770978a578837b28e5f7b1af60d981b2c965fc0`; review package
  `3406324aa417cf2f938b126d0393fa98184a1ad3dbb4acbfe536a76fcb0beabc`) with no further correction round. The instruction
  is kept outside Git with a SHA-256 sidecar (`50c7d55915ef5dbd0fbb2c6d576d7ba53f2d2a63adb4e47b10f6b3735d0f9fb0`).
- Purpose (authorization §3): the local POS side of the integrated card lifecycle — a durable provider-attempt sibling
  journal; `start` through `AuthenticatedCardChargeTransport`; waiting and status checks; safe handling of declined,
  unknown, anomaly and unavailable results; the provider recording leg, persisted before its first send and without
  `expected_revision`; restart recovery; the manager Resume of a recoverable recording refusal; localized Card UI
  states. Every network call in this ticket's tests goes to a fake; no real Edge URL or provider profile is activated.
- Not authorized: wiring the provider profile (`index.ts` keeps `providerProfile: null`), calling Z-Credit, a
  credential, a terminal or a card, a deployment, a migration, a hosted or secret change, a push, a PR, a merge, a
  printer or APK action. No Codex review is requested; one focused fresh-context Claude delta review runs (§13).
- Branch `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001F-pos-card-flow` in its own worktree, created from the exact accepted
  head `148df092`; no upstream. Earlier payment branches, packages and evidence folders are preserved (no amend,
  rebase, reset, deletion or history rewrite). Main is recorded separately and is not merged into this stacked branch.

## 2. Source anchor (preflight 2026-10-30T13:22:46Z, read-only)

| Source | Head | State |
|---|---|---|
| Base: 001C correction (`…-001C-TRANSPORT-CORRECTIONS-001`) | `148df092f08e71e39abfcf493835a1d852cfa9f7` | accepted; tree `e770978a` verified |
| 001C card Edge transport | `71bfef5bc57df9434c628894119610f99101b1b6` | parent of the correction (`148df092~7`) |
| 001E W1 profile candidate (unwired) | `cf1ffacf7f1395a66d653f0a5862c0d6e1622546` | unchanged |
| 001E D-064 inbound money | `ca8edb03223a7ac453d5b3a934296023a1e6bc3f` | unchanged |
| 001E W1 lookup safety | `140be040fafb3f21f6af3cacfa8b8d81db251246` | unchanged |
| 001E G1 drop evidence (D-062) | `295cacb6c50226da9cba99e769fac0680ee14fcc` | unchanged |
| 001E Edge adapter | `d545662476cea8cfae41729b15034dc713e10a19` | unchanged |
| 001D ledger publication (#370, draft) | `54b19ab58ce72a2fa9a43860e31181a08222b254` | unchanged; ancestor of the base |
| D-061 route r2 (#371, draft) | `53d6a6adc38f308b7ed6b0dd62177e6edd5ad5ce` | unchanged |
| origin/main (`git ls-remote`) | `5e8b3121eff4b36762668b5d587bb899c0826646` | recorded only; merge base `d2079820`, 12 commits / 56 files since |

- `supabase/functions/pos-card-charge/index.ts` line 19: `providerProfile: null,` (blob `7a3c5c97`), unchanged.
- Open PRs: #314 (`54346b37`, owns `apps/pos/lib/src/widgets/order_action_row.dart` and its two tests), #315
  (`4e8c81f6`, owns `packages/printing/**` and its downstream rendering / l10n tests), #370, #371. No open PR and no
  other worktree has a change on a file this branch plans to touch (§3).
- The pilot plan and checklist sequence 001F "after #314 merges or closes"; both PRs are open. The command room's
  authorization §2 settles this for local work: the reserved files stay untouched and the existing order action keeps
  opening the current payment sheet.

## 3. Exact files (allowlist)

Changed or added by this ticket — nothing else:

| Path | Purpose |
|---|---|
| `apps/pos/lib/src/data/provider_card_attempt.dart` | the sibling record, its strict codec, the canonical recording operation, the closed server facts |
| `apps/pos/lib/src/data/provider_card_store.dart` | the separately keyed durable journal (house `shared_preferences` envelope idiom) |
| `apps/pos/lib/src/data/provider_card_edge.dart` | `start` / `status` / `release` bodies over `AuthenticatedCardChargeTransport`; direct kind mapping; the closed answer parse |
| `apps/pos/lib/src/data/provider_card_recording.dart` | the recording leg over the existing `sync_push` transport and its classifier |
| `apps/pos/lib/src/data/provider_card_capability.dart` | the terminal posture parse and the fresh manager proof (`pin_session_capabilities`) |
| `apps/pos/lib/src/data/staff_capabilities.dart` | narrow: one optional `cardTerminal` posture field parsed from the same `branch_features` |
| `apps/pos/lib/src/state/provider_card_controller.dart` | the provider-card controller: single flight, polling leases, recording and Resume |
| `apps/pos/lib/src/format/provider_card_presentation.dart` | state → localized title, body, tone and icon |
| `apps/pos/lib/src/widgets/provider_card_payment_view.dart` | the card attempt view inside the payment sheet |
| `apps/pos/lib/src/widgets/cash_payment_sheet.dart` | tender gating by posture, the card terminal option, routing to the card view |
| `packages/l10n/lib/l10n/app_{en,ar,he}.arb` + the four generated `app_localizations*.dart` | AR / HE / EN keys for 001F only |
| `apps/pos/test/provider_card_*_test.dart`, `apps/pos/test/support/provider_card_fakes.dart` | focused tests and fakes |
| `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001F_EXECUTION.md` | this packet |

Existing payment tests are edited only where the changed behaviour reaches them directly (none expected; any edit is
named in §14). Reserved and protected, byte-identical to the base: `order_action_row.dart` and #314's two tests;
`packages/printing/**` and #315's rendering / l10n tests; kitchen ticket, reprint, printer and receipt code;
`supabase/**` (functions, migrations, SQL tests, `config.toml`); `.github/**`; `packages/data_remote/**` and
`packages/auth_identity/**`; Dashboard, KDS, Kiosk, Admin, Storefront and web-order source; Android release, signing
and version files; every `pubspec.yaml` and `pubspec.lock`. The base payment kernel — `payment_attempt.dart` (the
26-key record), `payment_attempt_store.dart`, `payment_repository.dart`, `payment_replacement_block.dart`,
`payment_safety.dart`, `payment_controller.dart` — is not changed (§9.4).

`staff_capabilities.dart` is the one existing data file touched besides the sheet: the authorization (§9) requires
the proven server capability, and the documented reading point is the PIN-session probe that file already makes
(DEPLOYMENT §18.4; **D-058** point 8: "the POS reads its branch features when the PIN session starts"). The change adds
one field and one parse call; the existing fields and their parsing are unchanged.

`l10n` ownership: the pilot plan's §7 allowlist gives `packages/l10n` to 001C and none to 001F, while the 001C packet
moved the strings to 001F and recorded the misalignment as an open documentation item. The command-room authorization
for this ticket names `packages/l10n` (AR / HE / EN source keys and generated output for 001F only); this packet follows
it and edits neither the pilot plan nor the checklist. The regeneration flips `packages/l10n/pubspec.yaml`
`generate: false → true` for the run and restores it byte for byte; the committed manifest is unchanged (§14 proves it).

## 4. Verified contracts (read at the base)

### 4.1 The Edge requests (`lib/request.mjs`; API §4.55.1)

Every body carries exactly `action`, `pin_session_id` (lowercase UUID), `device_id` (lowercase UUID),
`device_session_token` (1–4096 characters, no control character) and `attempt_id` (canonical lowercase UUID v4 =
the attempt's `local_operation_id`); unknown keys are `invalid_request` (400).

- `start` + `mode`, `amount_minor` (`^[1-9][0-9]{0,10}$`, ≤ 99 999 999 999), `currency_code` (`^[A-Z]{3}$`); LIVE adds
  `order_id` (lowercase UUID) and `expected_revision` (0 … 2 147 483 647); TEST forbids both.
- `status` + optional `source` (`auto` default | `operator`), `recording_refused` (boolean) and `refusal_code` (present
  exactly when `recording_refused` is true; one of the eleven recording hints).
- `release`: the common keys only. `free_order` is a manager tool and is not part of this ticket (§12).

The device-session token is a credential: it is read from the boot credential store at send time
(`onlineOrderInboxSecretStoreProvider`, the precedent of the online inbox and the background alerts), checked against
the PIN session's device, placed in the body for that one exchange and never persisted, logged or returned.

### 4.2 The Edge answers (`lib/envelope.mjs`; API §4.55.4)

- Envelope (200): exactly `ok:true`, `attempt_id`, `state` ∈ {`sent`, `approved`, `declined`, `unknown`, `released`},
  `classification` ∈ {`in_progress`, `freed`, `provider_anomaly`, `declined`, `recorded`, `orphan_approved`,
  `approved_unrecorded`, `resolved`, `test_sent`, `test_unknown`, `test_released`, `test_approved`, `test_declined`},
  optional `provider_return_code`, `refusal_code` (`release_failed` or a recording hint), `anomaly_code` (seven tokens),
  `resolution` (`provider_voided` | `provider_refunded` | `test_closed`), `recorded`, `recoverable` + `resume_count`
  (both or neither, 0 … 3), `payment_id` (only with `recorded:true`), `amount_minor`, `currency_code`, `server_ts`.
- Refusal (200 unless 400 / 401 / 503): `ok:false`, `error` (thirteen tokens), optional `detail` (twelve tokens),
  `attempt_id` + `attempt_state` (both or neither), optional `server_ts`.
- The transport (001C, corrected) returns a 200 unread (`CardChargeAnswered`), or a failure kind: `notSent`,
  `unauthenticated` (401), `notApplied` (400 / 403 / 404 / 405), `uncertain` (everything else, every 503 included, a
  timeout, a lost connection, an unreadable answer). No kind is a decline or an approval.
- With `providerProfile: null` the shipped Edge never creates an attempt: `start` answers 200 `card_payments_disabled`
  (master flag off) or 503 `provider_unavailable` (→ `uncertain` at the POS), and a later `status` answers 200
  `attempt_not_found`.

### 4.3 The recording leg (`20261023225657_bizbot_zcredit_001d_server_ledger.sql`; API §4.55.7)

- The server recognises the leg by identity: a `payment.create` whose `local_operation_id` is a provider attempt of
  the same organization and device. The canonical payload is exactly
  `{"order_id": <attempt order, lowercase text>, "tender_type": "card", "amount_tendered_minor": <attempt amount>}` —
  no `expected_revision`, no `provisional_receipt_number`; `card_attempt_mark_recording_result` treats any other payload
  as non-canonical (`nonrecoverable_refusal`).
- The leg is the only operation of its `sync_push` call (otherwise `single_operation_required`, nothing memoized).
- Answers for the leg: the applied 17-key `record_payment` result (`method:'card'`); guard refusals
  `provider_recording_refused` + `detail`, `amount_mismatch`, `card_context_lost`; the pre-ledger
  `test_attempt_not_recordable` (no sync row); `record_payment` refusals (`permission_denied` returned; `rejected` +
  SQLSTATE + `detail` `precondition_failed` / `revoked_employee` / null); the revoked-device `rejected` + `detail`
  `revoked_device`; the idempotency `conflict`; `pending` answers `transient_failure`, `dependency_not_ready`,
  `single_operation_required`, `resume_authority_required`; a replayed rejection carrying `resume_denied`.
- After any refusal the POS reports it through `status` (`recording_refused:true`, `refusal_code` = the hint); the
  server derives the stored token, `recoverable` and `resume_count` itself.
- Resume: the same operation object (`local_operation_id`, `operation_type`, `target_entity`, `target_id`,
  `client_created_at`, `payload`) plus the top-level sibling `recording_resume` = the `resume_count` the manager acted
  on (a JSON integer 0 … 3), the only operation of its call, under a manager-or-higher PIN session on the same device.
  At most three authorized Resumes; a `resume_denied` consumes nothing.

### 4.4 The terminal posture (`app.pin_session_capabilities`; API §4.30b, §4.55.8 / .9)

`branch_features.card_terminal_mode` (`test` | `live`) and `branch_features.card_terminal_enabled` (boolean) are present
only while the session's exact device has a `configured`, `enabled` or `draining` terminal binding; both absent
otherwise. `enabled` is true only when the operator revision is on, in its window and mode, and the binding is
`enabled`; `configured`, `draining`, revision OFF and a mode mismatch all read `enabled:false`. The Edge master flag is
invisible to the POS (a `start` may still answer `card_payments_disabled`). The lifecycle itself is never exposed.

## 5. The journal — a separately versioned sibling record

### 5.1 Placement and keys

- The 26-key base `PaymentAttempt` and its envelope (`restoflow.pos.payment_attempts.v1.<scope>`) are not touched:
  no key, value, version or quarantine rule of the base changes. The provider record lives in its OWN storage family
  beside it — the precedent of `order_edit_slip_store.dart` (a second, separately keyed sibling family with its own
  schema version) — and follows the total, never-throwing decoding discipline of `payment_replacement_block.dart`
  (strict map conversion, exact key sets, canonical instants).
- Storage key: `restoflow.pos.provider_card_attempts.v1.<PosSyncScope.key>` (the same sanitization as the base key).
- Envelope: exactly `{"version": 1, "attempts": [<record>, …]}`.
- With no posture and no card action the key is never written. The payment sheet still reads the journal (§7.2), and a
  hand-recorded Card send reads the posture fresh (§9.1).

### 5.2 Record schema version 1 (every key always present; a nullable key carries an explicit `null`)

| Key | Type / domain | Frozen? |
|---|---|---|
| `schema_version` | integer `1` | yes |
| `attempt_id` | canonical lowercase UUID v4; the provider attempt id AND the recording `local_operation_id` | yes |
| `organization_id`, `restaurant_id`, `branch_id`, `device_id` | non-empty strings; must equal the scope | yes |
| `identity_key` | `srv:<order_id>` | yes |
| `order_id` | non-empty; LIVE: canonical lowercase UUID | yes |
| `order_number` | display code, 1–64 characters | yes |
| `mode` | `live` \| `test` | yes |
| `amount_minor` | integer 1 … 99 999 999 999 | yes |
| `currency_code` | `^[A-Z]{3}$` | yes |
| `expected_revision` | LIVE: integer 0 … 2 147 483 647; TEST: `null` | yes |
| `employee_profile_id` | string or `null` — the initiating employee, attribution only | yes |
| `client_created_at` | canonical UTC instant (`DateTime.toUtc().toIso8601String()`) | yes |
| `start_in_doubt` | boolean — a `start` send began and its result is not yet recorded | |
| `start_may_have_executed` | boolean, sticky — some `start` call may have executed | |
| `start_last_sent_at` | canonical instant or `null` — when the last `start` send began (device clock), stamped in its persist-before-send write, before the credential read and the 001C exchange; each send of an attempt is stamped later than the one before it (one millisecond after it when the clock has not moved on), so the stamp names one send — the send a settle-window wait is about (§7.3) | |
| `start_outcome` | `null` \| `not_sent` \| `auth_required` \| `not_applied` \| `uncertain` \| `answered` \| `refused` | |
| `start_refusal` | `null` \| `{"error", "detail"}` — closed Edge tokens of a 200 `start` refusal | |
| `server` | `null` \| `{"state", "classification", "recorded", "refusal_code", "anomaly_code", "resolution", "recoverable", "resume_count", "payment_id", "server_ts"}` — the last closed envelope, every key present | |
| `server_not_found_at` | canonical instant or `null` — when the `status` request that answered `attempt_not_found` was sent, recorded only once the settle window had passed for that same send (§7.3); a new `start` send clears it | |
| `recording` | `null` \| the canonical operation (§8.1), built once | built once, then frozen |
| `recording_in_doubt` | boolean | |
| `recording_may_have_executed` | boolean, sticky | |
| `recording_outcome` | `null` \| `applied` \| `unconfirmed` \| `not_sent` \| `auth_required` \| `not_applied` \| `pending` \| `refused` \| `collision` \| `resume_authority_required` \| `resume_denied` | |
| `recording_refusal` | `null` \| one of the eleven recording hints | |
| `refusal_report_pending` | `null` \| a recording hint not yet reported through `status` | |
| `resume_denied` | `null` \| one of the thirteen `resume_denied` tokens | |
| `payment` | `null` \| `{"payment_id", "receipt_number", "order_status"}` from this device's applied reply | |
| `receipt_reserved_at` | canonical instant or `null` — the one automatic receipt, reserved once | |
| `safety_stop` | `null` \| `test_attempt_not_recordable` \| `mode_mismatch` \| `amount_mismatch` \| `attempt_conflict` \| `recording_contract` | |
| `closed` | `null` \| `abandoned` \| `set_aside` — a local closure the cashier chose (§7.3) | |
| `updated_at` | canonical instant | |

Cross-field rules (a record breaking any is quarantined, never repaired): LIVE requires a UUID `order_id` and an
`expected_revision`; TEST forbids `expected_revision`, `recording`, `payment` and `receipt_reserved_at`; a non-null
`start_outcome` or a true `start_in_doubt` / `start_may_have_executed` requires `start_last_sent_at`; `start_refusal` is
present exactly when `start_outcome` is `refused`; `server` requires `start_may_have_executed`; `server` is internally
consistent (the classification family matches the record's `mode`; `recorded` only with `recorded`; `payment_id` only with
`recorded:true`; `recoverable` / `resume_count` together and only for `approved_unrecorded` / `orphan_approved`;
`anomaly_code` only for `provider_anomaly`; `resolution` `test_closed` only for TEST); `recording` requires LIVE and its
`local_operation_id` = `attempt_id` and its payload = the canonical payload of the frozen fields; every `recording_*`
value requires `recording`; `payment` is present exactly when `recording_outcome` is `applied`;
`receipt_reserved_at` requires `payment`; `refusal_report_pending` requires `recording_outcome` `refused` or
`collision`; `resume_denied` is present exactly when `recording_outcome` is `resume_denied`; `closed: abandoned`
requires that no `start` may have executed; `server_not_found_at` requires no `server` facts and a `start` that is in
doubt or may have executed.

*Corrected 2026-10-31 (correction packet §4): one rule more, R7d — a `closed` value never hides an unresolved
attempt: without it the record must be final already, or one that may be set aside.*

Never persisted: a credential or device-session token, a PIN or PIN-session id, a terminal / PinPad identifier or
reference, a provider key, a PAN, masked PAN, token, expiry or any card datum, `provider_return_code`, a raw provider
or backend payload or message, a service-role value, customer data.

### 5.3 Reading, quarantine and retention

- The decoder is total: every input — a non-map, a non-string key, a missing or unknown key, a wrong type, an
  unknown token, a non-canonical instant, a broken cross-field rule, an unknown `schema_version` — yields a typed
  result, never an exception.
- An unreadable envelope (bad JSON, an unknown top-level key, `version` other than the integer 1, `attempts` not a
  list) quarantines the whole family: no record is shown and no write is attempted (a write could destroy bytes it
  cannot read). An unreadable entry, or an entry of another scope, is kept and re-emitted on every write as its
  decoded and re-encoded JSON value: its spacing may change, and so may anything the JSON codec cannot keep exactly (a
  duplicate key, an integer beyond 64 bits).
- Any quarantine blocks NEW integrated starts on this till until it is resolved — by a build that can read the record,
  or by an operator procedure under its own authorization; this ticket adds no in-app path that discards or archives a
  stored money record. Readable attempts stay fully recoverable. Other tenders are unaffected, except that the legacy
  Card stays hidden on a LIVE till.
- Retention: at most 200 entries; an append beyond it drops the oldest in-scope, readable entries that are terminal
  (§7.3) or recorded (the order is paid), and never any other open entry, an unreadable or a foreign one (a bounded
  overshoot instead).
  *Corrected 2026-10-31 (correction packet §5, §6): the 200 entries are an admission bound — when no safe and final
  entry is left to drop, a new start is refused (`journalFull`: nothing minted, written or sent) instead of growing
  the journal; and an envelope holding one `attempt_id` twice, or two open records of one order and mode, is
  quarantined whole like an unreadable one.*

### 5.4 Writes

- Every write runs in one isolate-wide serial section per storage key, re-reads the stored bytes inside it, builds the
  whole new envelope before touching storage, and is durable only when `setString` reported success. Any other
  outcome throws `PosPersistenceException`, and the caller sends nothing.
- `createIfAbsent` adopts an open attempt of the same order instead of creating a second (two sheets or two provider
  graphs over one store see one record); `update` applies a transition to the freshest stored record (read inside the
  serial section, so a stale in-memory copy never overwrites newer facts) and refuses an absent one.
  *Corrected 2026-10-31 (correction packet §5, §6): `createIfAbsent` mints the new attempt inside its serial section
  and only once the journal admits it, and no write ever stores an envelope the store would itself quarantine.*
- Every record written is decoded again first: a record this decoder would quarantine is never written
  (`PosPersistenceException`, and the caller sends nothing).
- Persist-before-send: the record exists, and `start_in_doubt` / `recording_in_doubt` is durably true, before any
  handoff; a crash in between therefore reads back as "may have been sent".

## 6. Transport-result mapping — the card kinds directly

`classifyTransportFailure` of `payment_repository.dart` is never used for a card result (it still treats any 4xx but
408 / 425 / 429 as not applied); a static test pins its absence from the provider files.

| Kind | `start` | `status` | `release` |
|---|---|---|---|
| `notSent` | `not_sent`; `start_in_doubt` cleared; no ledger effect of this call; the SAME body may be re-sent only by an explicit cashier action after a fresh session and device check | note "not sent"; attempt unchanged | note; attempt unchanged |
| `unauthenticated` | `auth_required`; the attempt is preserved; explicit resend of the SAME identity after a fresh sign-in (the same PIN session is not refused locally: a 401 can clear with an access token the SDK refreshes, and the server decides); no replacement | note "sign in again"; attempt unchanged | note |
| `notApplied` | `not_applied`: an application / configuration refusal, never a decline; no retry, no new attempt; the journal keeps it; the safe refusal path is another tender | note; attempt unchanged | note |
| `uncertain` | `uncertain`; `start_may_have_executed` true for good; `start` is NEVER sent again for this attempt; only `status` resolves it (restarts included) | note "unavailable"; back-off | note "not confirmed" |
| answered | the closed parse of §4.2 (§7) | the closed parse | the closed parse |

A resend of a `not_sent` or `auth_required` start is, to the server, a first start: it also needs the posture to still
permit a start (§9.1; otherwise nothing is sent and the note says the terminal is unavailable). A posture not known yet
is read once more first, the attempt showing as being prepared meanwhile; still unknown, nothing is sent and the note
says the settings could not be checked; a card view gone by the end of the read sends nothing (nobody watches the
terminal it would prompt).

A `status` answered 200 `permission_denied` (a PIN session outside the four card roles) proves nothing: the note says
this role cannot act on card payments, automatic checks back off as after an unreadable answer, and it is never the
context proof a recording send waits for (§8.2).

A timeout before the handoff is `uncertain` (001C). An answered 200 that fails the closed parse (an unknown key, a
missing field, a wrong type) changes nothing and reads as "status unavailable". A well-formed envelope that contradicts
the frozen attempt — another amount or currency, a classification family of the other mode — is a safety stop
(`amount_mismatch` / `mode_mismatch`), and so is a `start` refusal `conflict` carrying attempt facts (the same identity
holds different frozen fields: `attempt_conflict`).

`start` 200 refusals are definitive no-claim answers: `card_payments_disabled`, `payment_in_progress`,
`order_already_settled`, `order_not_chargeable`, `precondition_failed` + {`ineligible_order_state`,
`max_live_amount_exceeded`, `max_test_amount_exceeded`, `currency_not_supported`, `no_open_shift`,
`no_active_drawer`}, `conflict` (revision), `conflict` + `identity_in_use`, `amount_mismatch`, `permission_denied`.

## 7. State and UI matrix

### 7.1 Presentation (derived from the record; one row per state)

| State | Derived from | Shown | Actions |
|---|---|---|---|
| preparing | a `start` of this device in flight (or a retry reading the posture first) while no earlier send of it may have executed (the one in flight may have) — in memory only; it takes precedence over the derived states below; after a restart the record's own state is shown, and after a rebuild the new controller world keeps showing "preparing" (the carried busy, §10) until the earlier world's start ends, then shows what it stored | "Preparing the card request" | — (no action while it lasts) |
| not sent | `start_outcome` `not_sent`, never handed off | "The card request was not sent" | Send the same request; Cancel this request; Close |
| sign in again | `auth_required` | "Sign in again, then send the same request" | Send the same request; Take payment another way; Close |
| unavailable | `not_applied` | "Card terminal payment unavailable — refused before processing" | Take payment another way; Close |
| refused | `refused` (a §6 no-claim refusal) | the refusal in words (switched off, in progress, already paid, nothing to charge, order changed, open a shift, above the limit, currency, role) | Take payment another way; Close |
| result not confirmed | `uncertain` / in doubt, no server facts, no settled not-found | "Result not confirmed — do not charge again" | Check status; Close (auto checks while open) |
| not found | `attempt_not_found` recorded for a request about the last `start` send, sent once the 200 s settle window had passed on the process's monotonic clock (§7.3) | "No card payment was created" | Check status; Take payment another way; Close |
| waiting | LIVE `in_progress` with state `sent` / `unknown` | "Waiting for the customer at the terminal" | Check status; Cancel on the terminal; Close (auto checks while open) |
| cancel requested | state `released` | "The provider confirmed the cancel — a charge may still exist" | Check status; Close (auto checks while open) |
| approved, recording | `approved_unrecorded`, leg not yet answered | "Approved — completing BIZBOT recording" (never "Paid") | the first send is automatic; when it did not happen (a restart, a lost session): Send the recording again (cashier+, after a fresh proof); Check status; Close |
| recording not confirmed | leg `unconfirmed` / `not_sent` / `not_applied` / `pending` / `auth_required` | "Approved — recording not confirmed" | Send the recording again (cashier+, after a fresh proof); Check status; Close |
| recording refused | leg `refused` / `collision`, `recoverable:true`, count < 3 | "Approved — recording refused; a manager can resume it" + "Resumes used n of 3" | Resume recording (manager); Check status; Close |
| manager must send | leg `resume_authority_required` | "A manager must send this recording" | Send the recording (manager); Check status; Close |
| resume refused | leg `resume_denied` | the token in words | Check status; Resume recording (manager, only while still recoverable); Close |
| recorded | leg `applied`, or envelope `recorded` | "Card payment recorded" | Done (the one success edge) |
| declined | `declined` | "Card declined — no payment was taken" | Take payment another way; Close |
| unlocked | `freed` | "Unlocked by a manager — no charge" | Take payment another way; Close |
| closed by an operator | `resolved` (voided / refunded) | "Closed by an operator" | Take payment another way; Close |
| needs reconciliation | `provider_anomaly`, `orphan_approved`, `approved_unrecorded` with `recoverable:false` after a refused or colliding leg, the Resume limit, a `safety_stop` (only `recording_contract`, raised on this attempt's own LIVE approval, yields to a later LIVE `resolved` or recorded answer; `test_attempt_not_recordable`, `attempt_conflict`, `mode_mismatch` and `amount_mismatch` never do, since the server's facts may then describe another attempt) | "A charge may exist — do not charge again or record it another way; ask a manager" | Check status (it also delivers a refusal report still owed, §8.4); Close |
| automatic checks stopped | a `poll_limit` answer | "Check the status manually" | Check status (operator); Close |
| TEST in progress / approved / declined / closed | `test_*` | the TEST outcome; "nothing is recorded, the order stays unpaid" | Check status; Cancel on the terminal (while `test_sent` / `test_unknown`); Back to payment; Close |

Status, refusals and notes are text with an icon and a title; nothing is conveyed by colour alone. The state header is a
live region.

*Corrected 2026-10-31 (correction packet §4.2): a TEST attempt in progress, after a confirmed cancel or with a result
not confirmed offers no Back to payment and no set-aside — only Check status, Cancel on the terminal while it waits,
and "Close and resume later"; Back to payment remains for a final TEST result (approved, declined, closed), and a
TEST attempt proven to have no claim (not sent, sign in again, a settled not found) may still be set aside, as a LIVE
one may; the full TEST matrix is in the correction packet.*

### 7.2 What the sheet offers

- The payment sheet hydrates the card journal (and reads the posture) before any Confirm, beside the base attempt
  store; every tender waits while the journal is read again after a PIN-session or scope change.
- An OPEN attempt for the order (§7.3) replaces the tender form with the card view — no other tender, no new start, no
  manual Card while it is open. A terminal attempt of this sheet session stays visible until the cashier leaves it —
  including one whose first answer closed it before the view was drawn (a `card_payments_disabled` refusal must be
  read, not skipped). The view is left only when no set-aside is needed or the set-aside was stored; an attempt still
  open is never hidden.
  *Corrected 2026-10-31 (correction packet §4.2, §4.4): an open TEST attempt covers the form as an open LIVE attempt
  does, whatever the lab toggle, until it is final, or until the cashier sets it aside once it is proven to have no
  claim; a final TEST result this sheet showed stays until it is left, with the lab off as in the lab. The limits are
  owner point D8 of the correction packet.*
- A hand-recorded Card is sent only on a posture read fresh at the send (§9.1). The sheet is busy while it is read (the
  TEST lab switch too), and after the read the Card is sent only if it is still the chosen tender and no card attempt
  for the order now shows. The chosen tender follows what the posture offers: a terminal choice whose option went away
  falls back to Cash (never to the hand-recorded Card), and so does a hand-recorded Card a LIVE till hides.
- Tender gating by posture (§9). The integrated option starts a NEW attempt only with an authoritative server order
  (`srv:<uuid>`), an amount ≥ 1, a currency the provider can encode (ILS, the pilot's only currency) and, for LIVE, an
  authoritative `expected_revision` (otherwise the existing "refresh the order" banner).
- "Recorded" pops the sheet with `true` (the one authoritative success edge); the existing reconcile runs and the
  automatic receipt is requested once, only when this device's own recording reply reserved it.

### 7.3 Open, terminal and set-aside

- Open (blocks a new start for the order and keeps the card view): preparing; not sent; sign in again; result not
  confirmed (including a not-found still inside the settle window); waiting; cancel requested; every approved state
  that is not recorded; needs reconciliation; recorded (the order is paid).
- Terminal (does not block): `not_applied`; a `refused` start; declined; unlocked (`freed`); closed by an operator
  (`resolved`); a settled not-found once set aside; `closed` `abandoned` / `set_aside`; TEST approved / declined /
  closed. TEST attempts never block a LIVE start or another tender (a TEST attempt claims no order).
  *Corrected 2026-10-31 (correction packet §4.2): on this till an open TEST attempt now covers its order's tender form
  — no other tender, no new start, no hand-recorded Card — until it is final, or until it is set aside once proven to
  have no claim. It still claims no order on the server or on another till, and a LIVE start is never adopted into it
  (adoption and uniqueness are per mode), but both modes share the 200-record bound.*
- "Take payment another way" from not found and sign in again persists `closed: set_aside`; "Cancel this request"
  from not sent persists `closed: abandoned`. Neither is offered while a charge may exist. TEST attempts may be set
  aside at any time.
  *Corrected 2026-10-31 (correction packet §4.2): the same rule holds for TEST — a TEST attempt is set aside only from
  not sent, sign in again or a settled not found; never while it waits, after a confirmed cancel or while its result
  is not confirmed.*
- The settle window is 200 s: the platform's 150 s request idle timeout (it runs from the request's arrival), plus the
  001C exchange deadline (`posCardChargeTimeout`, 40 s, which includes the SDK's access-token step), plus 10 s for
  transit. Once it has passed after a `start` request could last have been handed off, that request can no longer
  create a claim, so `attempt_not_found` proves no attempt exists. Inside the window `attempt_not_found` stays
  inconclusive and is not recorded (the 001C packet's handoff to 001F).
- The window is measured on the process's monotonic clock, never on the wall clock, and bound to the send it is about
  (`start_last_sent_at`, unique per send of the attempt): from the end of a `start` exchange this process ran (nothing
  of it can be handed off later), or from the first time this process saw a send it did not run (the hydration of a
  record in doubt, or a check about it). The latter is sound because a send that another controller world or an
  earlier process began can no longer be handed off once that world has ended (its handoff checks refuse) or that
  process has died; two live controllers over one journal are not a configuration the POS ships. A wait on one send
  never measures another; a `start` whose outcome proves it had no effect (`not_sent`, `auth_required`,
  `not_applied`) leaves no wait; a new process measures again from its hydration. `attempt_not_found` is recorded only
  for a request about that same send, sent once the window had passed — that recorded decision is what "not found"
  shows, so no wall-clock step changes it — and a new `start` send clears it. A new identity is never minted
  automatically and never while an attempt is open (001D packet §4.3).

## 8. The recording leg and the Resume

### 8.1 The canonical operation

```json
{"local_operation_id": "<attempt_id>", "operation_type": "payment.create", "target_entity": "payment",
 "target_id": "<uuid v4 minted once>", "client_created_at": "<instant minted once>",
 "payload": {"order_id": "<attempt order_id>", "tender_type": "card", "amount_tendered_minor": <amount_minor>}}
```

- Built once, when the attempt is first seen `approved_unrecorded`, persisted with `recording_in_doubt: true` before its
  first send, and reused byte for byte by the first send, every resend, a restart and a Resume. `expected_revision` is
  absent: the provider-leg exception to PDR-003 (**D-057** point 2) lives in this sibling record only; the base
  `PaymentAttempt.toSyncOperation` and the PDR-003 gate of `PaymentController` are unchanged for cash, card, bit and
  external.
- `target_entity` / `target_id` / `client_created_at` follow the base attempt's convention (`payment`, a client UUID);
  the Resume guard compares them with the stored row (`operation_mismatch` otherwise), so they never change.
- A Resume adds only `"recording_resume": <n>` beside `payload` — the envelope's `resume_count` the manager acted on.

### 8.2 Sends

- The leg is pushed alone: `sync_push` with `p_pin_session_id`, `p_device_id` and `p_operations: [<operation>]` over the
  same `SyncRpcTransport` the base payment uses (no service-role value).
- The first send is automatic, right after an envelope (`start` or `status`) said `approved_unrecorded` — that answer
  is the fresh context proof (API §4.55.7: the leg waits for a fresh proof, so a pairing outage never memoizes
  `revoked_device`). Every later send is explicit and runs `status` (`source: operator`) first; it sends only if that
  answer still says `approved`, not recorded.
- A never-delivered or unconfirmed leg may be re-sent by an active cashier or higher on the same device (no provider
  call; the server replays a committed answer). Once a rejected sync row exists, only the manager Resume applies.
- Only an envelope of that very `status` exchange is the fresh proof: a readable refusal (a role that may not act, a
  poll limit) proves nothing and nothing is sent.
- Every send is re-proven on the FRESHEST stored record inside its persist-before-send write: approved and not
  recorded, no payment, nothing closed or stopped, and — for the automatic first send — never built or sent before. A
  leg goes out under the PIN session whose proof allowed it or not at all: its sender is taken before anything can
  rebuild the controller, and a leg whose write returns into another PIN session or scope is not sent there; it reads
  "may have been sent" and waits for an explicit resend after a fresh proof. An answer applied after a payment was
  recorded never overwrites it.

### 8.3 Leg answers

| `sync_push` answer | `recording_outcome` | Next |
|---|---|---|
| applied (the base classifier's full applied tuple, `method:'card'`) | `applied` | recorded; the receipt reserved once |
| transport `auth` | `auth_required` | sign in; send the same leg |
| transport `transient` `device_session_unverified` | `not_sent` | send again after the check |
| a raised server error (a SQLSTATE: the whole call rolled back, e.g. an invalid PIN session or a support session) | `not_applied` | send again |
| any other transport failure, an unreadable or mismatched reply | `unconfirmed` | send again (explicit) |
| `pending`: `transient_failure`, `dependency_not_ready`, `single_operation_required` | `pending` | send again (explicit, alone) |
| `pending`: `resume_authority_required` | `resume_authority_required` | a manager sends the same leg |
| a replay carrying `resume_denied` | `resume_denied` | re-read `status`; nothing consumed |
| idempotency `conflict` | `collision` | report hint `conflict` |
| `provider_recording_refused` (+ `detail`), `amount_mismatch`, `card_context_lost`, the base refusals | `refused` (hint) | report the hint through `status` |
| `rejected` + `revoked_device` | `refused` (`revoked_device`) | report; never recoverable |
| `test_attempt_not_recordable` (no sync row) | `safety_stop` | a defect: never retried, never reported |
| a pre-dispatch `invalid_payload` / `invalid_envelope` / `unknown_operation_type` | `safety_stop` (`recording_contract`) | a defect |

The applied tuple and the base refusal tuples are read by the unchanged `RealPaymentRepository.classifyEnvelope` on a
transient, never-persisted `PaymentAttempt` view of the leg (same identity, order and `card` tender); the provider
tuples are matched first, exactly.

### 8.4 The refusal report and the Resume

- After a refused leg the hint is persisted as `refusal_report_pending`, then reported through `status`
  (`recording_refused:true`); an envelope answering the request that carried it clears it. A report that cannot be
  made now stays pending (the journal keeps it) and goes with the next explicit Check status, which carries the hint
  whenever one is owed, or with the Resume, under the session signed in then. That matters: the session that received
  a `revoked_employee` or `permission_denied` refusal is the one the Edge's context proof refuses (401, or
  `permission_denied`), so another person signs in and checks the status; until the report is stored the attempt stays
  `approved_unrecorded` with `recoverable:false` (reconciliation, no Resume). Automatic checks never carry the report.
- The Resume is offered only when the latest envelope says `approved`, not recorded, `recoverable:true` and
  `resume_count` < 3. Before dispatch the POS re-proves, in order: a pending report; a fresh `pin_session_capabilities`
  read whose `role` is `manager`, `restaurant_owner` or `org_owner` (an active PIN session and membership); a fresh
  `status` (an active device session) that still says `recoverable:true` with the same count. It then sends the stored
  operation with `recording_resume` = that count. The server's guard stays the authority (`resume_denied` tokens).
- A cashier resend of a row a Resume reopened answers `resume_authority_required` and stays pending; only a manager
  sends it again (without a new `recording_resume`).
- No Resume or resend ever calls the provider; none mints an identity.

## 9. Posture, tenders and the TEST lab

### 9.1 The posture

`PosStaffCapabilities.cardTerminal` is parsed from the same `branch_features` the PIN-session probe returns:

| Probe | Posture | Legacy Card | Integrated card |
|---|---|---|---|
| both keys absent (or no `branch_features`) | absent | shown; sending it reads the posture again (held with a note if that read fails) | none |
| `live` + `enabled:true` | live, starts permitted | hidden | "Card terminal" (LIVE start) |
| `live` + `enabled:false` (configured, draining, revision off) | live, starts stopped | hidden | none; open attempts still recover |
| `test` + `enabled:true` | test | unchanged | "Card terminal · TEST" only while the lab toggle is on |
| `test` + `enabled:false` | test | unchanged | none |
| one key only, a wrong type or an unknown mode | unknown | shown; sending it reads the posture again; still unknown: held with a note, nothing minted or sent | none |
| the probe failed or has not answered | unknown | shown; sending it reads the posture again; still unknown: held with a note, nothing minted or sent | none |
| no transport or no session (demo, tests) | absent | unchanged | none |

Every hand-recorded Card send reads the posture fresh first (a binding may have been configured since the PIN session
began), and only a proven posture permits it: no terminal binding, or a TEST one. A till found LIVE refuses it in place
("this till takes card payments on the card terminal") and offers its terminal when LIVE starts are permitted for an
eligible order (otherwise it says card payments are unavailable on this till); a posture that cannot be read holds it
with a note, and every Confirm is the retry. This is a deliberate fail-closed choice: a hand-recorded Card pushed on a
LIVE till is refused by the server `card_terminal_required`, which the unchanged base classifier reads as unconfirmed
and parks in recovery for good (§9.4), after the cashier may already have charged the card outside BIZBOT;
authorization §9 forbids that fallback during an outage, and an unread till may be such a till. Choosing the chip
while the posture is unknown reads it at once, so the cashier learns before charging anything. The chip itself stays on
screen, so an ordinary till's tender form does not change. The narrow cost, for the owner (§14): on a till WITHOUT a
binding, a hand-recorded Card cannot be recorded while the capability probe keeps failing although `sync_push` would
work; cash, Bit and External are unaffected. The integrated option is never offered while the posture is unknown.

The fresh read never refreshes the PIN-session probe itself — every capability of the session (edit, tables, menu
availability, kitchen finishing, the drawer) hangs on it: it reads the probe's repository directly, one read at a
time; a read that fails is unknown and changes nothing else on the till; one that succeeds publishes only the card
posture it found, which stands until the probe answers again or the PIN session changes.

### 9.2 Kill switch and draining

`card_terminal_enabled` is advisory. A start under a closed revision, a draining binding or the Edge master flag off
answers `card_payments_disabled` — rendered as "switched off", never as a decline — and the manual Card stays hidden
on a LIVE till whatever the switch (no manual fallback during an outage, a kill switch or `provider_unavailable`).
`status`, `release` and the recording leg keep working while starts are stopped.

### 9.3 The lab toggle

A per-device, in-memory switch, default OFF, reset by every PIN-session change and shown only on a till whose posture
is `test`. It is UX only: it never overrides the server posture, never applies to LIVE and never persists. With it OFF
the sheet ignores TEST attempts (they claim no order and record nothing).

*Corrected 2026-10-31 (correction packet §4): the toggle decides only whether a TEST start may go out — a new TEST
attempt, or "Send the same request" for one never sent or answered "sign in again". With it OFF an unresolved TEST
attempt still covers its order's tender form on this till while that order is payable there, and stays recoverable
(Check status; Cancel on the terminal while it waits) within the limits of owner point D8 of the correction packet;
only a final TEST result is out of sight, except one the sheet showed before it turned final, until it is left.*

### 9.4 What stays as it is

`PaymentController`, the base attempt store, the base classifier and the 26-key record are unchanged — the provider
leg never passes through them, and its success reaches the order through the existing reconcile and the server's
receipt source. Not in this authorization and recorded for a separately approved ticket: the typed rendering of the
001D guard codes in other flows' classifiers (`payment_in_progress` / `card_terminal_required` in the base payment
classifier, `card_payment_in_progress` in the shift close, `payment_in_progress` on edit, void, discount and item
additions, API §4.35 item 4); the manager's `free_order` and cross-device operator tools; the snapshot key
`card_attempt_in_progress`.

## 10. Polling and concurrency

- One request in flight per attempt and per action family: a second `status` while one runs awaits it (an automatic
  and a manual check collide into one request); `start`, the leg, the Resume and `release` refuse to overlap.
- A controller rebuild (another PIN session or scope) cannot recall a request already handed off: the attempt stays
  marked on the wire until its exchange returns, and the new controller world shows the attempt busy until the
  operation that began it ends, then reads what it stored; nothing new is sent for the attempt meanwhile. Every state
  write of an ended world is dropped (a pending rebuild runs before the check), and once the container is disposed
  nothing is current: a late answer re-arms no timer and sends nothing.
- Automatic checks run only while the card view is visible, the app is resumed and the same attempt is current: a lease
  per visible view; closing the sheet, covering it with another route or pausing the app ends it and stops the timer
  (uncovering or resuming attaches again); the journal keeps the attempt; no background or hidden monitor exists. A
  controller rebuild stops every timer but keeps the leases of the views still shown, and the hydration that follows
  re-arms them.
- The journal is read only where a card call is possible at all: never in demo mode or in a build without an RPC
  transport (as the base payment controller hydrates only where it can send).
- Cadence: the first automatic check 3 s after the view attaches, then every 4 s (the Edge enforces 3 s between
  lookups); after an unreadable, unavailable or `uncertain` answer 8 s, 16 s, then 30 s until a readable answer; at most
  60 automatic checks per lease, then the view asks for a manual check. `source` is `auto` for these and `operator` for
  Check status. `poll_limit` stops automatic checks and shows the manual state; it is never a decline; Check status
  clears that note only when it can check (not while another request for the attempt is under way). Automatic checks
  never carry a refusal report; an explicit Check status carries one whenever it is owed (§8.4).
- Release: at most one request per explicit tap; "released" is provisional and never marks the order unpaid; Check
  status and the same attempt remain.
- A restart restores the same attempt from the journal and presents Check status; nothing is re-sent at hydration.

## 11. Tests (authorization §11 → files)

| Authorization item | Test file |
|---|---|
| Foundation / gate (feature off byte-identical; posture absent unchanged; LIVE hides; draining; profile null) | `provider_card_sheet_test.dart`, `provider_card_static_test.dart` |
| Journal (round trip, persist-before-start, restart, quarantine, no sensitive values, same identity and bytes) | `provider_card_journal_test.dart`, `provider_card_controller_test.dart` |
| Transport mapping (direct kinds; no generic classifier; 409 / 413 / 415 / 422 uncertain; no automatic retry; uncertain → zero later starts; explicit notSent retry same body) | `provider_card_edge_mapping_test.dart`, `provider_card_controller_test.dart` |
| Provider envelope (every state; malformed / mismatched fail closed; no raw provider field kept) | `provider_card_edge_mapping_test.dart` |
| Recording (no `expected_revision`; ordinary tenders keep it; revision move after approval; one `payment.create`; restart reuse; cashier resend; Resume cases; no provider call) | `provider_card_recording_test.dart` |
| Concurrency (one status in flight; auto / manual collision; sheet close stops polling; two UI instances; competing start refused once) | `provider_card_controller_test.dart`, `provider_card_sheet_test.dart` |
| TEST (no `payment.create`; no paid UX; `test_attempt_not_recordable` is a safety stop) | `provider_card_recording_test.dart`, `provider_card_sheet_test.dart` |
| Localization / accessibility (AR / HE / EN; RTL; semantics; no hard-coded strings; not colour alone) | `provider_card_sheet_test.dart` |
| Regression (cash, bit, external, manual card on an unmapped till; no `order_action_row` / printing change; receipt only on acceptance) | `provider_card_sheet_test.dart` + the existing payment suites |
| The review corrections (§13): rebuilds and disposal, two controllers over one journal, the send stamps, the fresh posture read | `provider_card_controller_test.dart`, `provider_card_recording_test.dart`, `provider_card_sheet_test.dart`, `provider_card_journal_test.dart`; most corrections are proven by a mutation (§14.2) |

Every Edge exchange goes to a fake `AuthenticatedCardChargeTransport` that classifies its scripted answers with the
real `classifyCardChargeAnswer`; `sync_push` and `pin_session_capabilities` go to a fake `SyncRpcTransport` that
models the provider-leg rules of §4.3; creating an `HttpClient` fails the test.

## 12. Gates still held

- `providerProfile` stays `null`; **Q-047** (the sealed non-settling TEST facility) and **Q-049** (key-format evidence)
  remain hard owner gates on every real provider action; E2-B, **Q-048**, **Q-050** and **Q-052** remain open; no
  vendor inquiry, terminal, card or hosted step is taken.
- Not built here: `free_order` and cross-device operator status; the other flows' guard-code classifiers (§9.4); any
  receipt change (**Q-052**, **D-053** point 8).
- Publication, the stack integration with main (the l10n files #370's `40147318` also changes) and the merge order of
  #314 / #315 / #370 belong to later, separately authorized steps.

## 13. Review

One focused fresh-context Claude delta review of the whole feature (base `148df092` → `7c29bcff`), each of its findings
re-checked refute-first by independent agents; then four closing checks, each a refute-first review of the previous
round's corrections by two to four lenses (from the third on, every finding of MEDIUM or higher also went to an
adversarial refuter). No Codex review is requested. Before this packet's commit `1a63a4c0`, two agents checked its text
against the code and the evidence. Each finding's verdict, disposition, round commits, tests and, where one exists,
mutation proof are recorded in the evidence (`review/REVIEW_DISPOSITIONS.md`); §14.3 summarizes them.

## 14. Results

### 14.1 Commits and scope

Base `148df092` (tree `e770978a`); no upstream; nothing pushed. Every commit names the Work ID:

| Commits | Content |
|---|---|
| `d073603a` | this packet, before any executable change |
| `a9ca61d1`, `482dcf23`, `7c29bcff` | the journal, Edge client, recording leg and controller; the card view, sheet and strings; the tests and fakes |
| `e241d95c` / `e41ce912` | the delta review's corrections / their tests |
| `c32aa8d7` / `ea2578de` | closing check 1's corrections / their tests |
| `a8d1f78d` / `01c581f2` | closing check 2's corrections / their tests |
| `708d3f6b` / `147f12c6` | closing check 3's corrections / their tests |
| `779925f5` | closing check 4's test corrections (tests only) |
| `fa12762e` / `6a92bfc3` | the packet accuracy check's code correction (R6e for a refusal hint) / its test; `fa12762e` is the last change to `lib/` |
| `1a63a4c0` | §5 – §14 of this packet brought in line with the code; no executable change |
| this commit | the disclosure of the main-checkout manifest incident (§14.6); no executable change |

25 paths changed (§3), every one inside the authorization's allowlist; no manifest or lockfile; no existing test file
was edited (every test change is in the new `provider_card_*` files). `order_action_row.dart` and #314's two tests,
`packages/printing/**` and #315's tests, the receipt rendering, the base payment kernel (§9.4), `supabase/**`,
`.github/**`, `packages/data_remote/**` and `packages/auth_identity/**` are byte-identical to the base; `index.ts` keeps
`providerProfile: null,`. `packages/l10n/pubspec.yaml` was set `generate: false → true` for the regeneration and
restored byte for byte (blob `5aa4f9d2` at the base and the head); `pubspec.lock` keeps blob `d0aba4d0`. Each ARB gained
101 `posCard…` keys (EN / AR / HE: 2 943 → 3 044 keys) and lost none.

### 14.2 Validation

| Head | format, analyze, l10n check, three CI guards | POS suite | l10n suite |
|---|---|---|---|
| `7c29bcff` | clean | 5 484 passed, 27 skipped, 1 failed: a widget test with no RPC transport timed out while the card journal was read (fixed in `e241d95c`: the journal is read only where a card call is possible) | 95 / 95 |
| `e41ce912` | clean | 5 508 passed, 27 skipped, 0 failed | 95 / 95 |
| `ea2578de` | clean | 5 521 passed, 27 skipped, 0 failed | 95 / 95 |
| `01c581f2` | clean | 5 529 passed, 27 skipped, 0 failed | 95 / 95 |
| `147f12c6` | clean | 5 531 passed, 27 skipped, 0 failed | 95 / 95 |
| `779925f5` | clean | 5 533 passed, 27 skipped, 0 failed | 95 / 95 |
| `6a92bfc3` (last code and test change) | clean | 5 534 passed, 27 skipped, 0 failed | 95 / 95 |

The card suites at `6a92bfc3`: journal 20, Edge mapping 12, controller 47, recording 31, sheet 25, static 3 (138).
Every Edge exchange goes to a fake; creating an `HttpClient` fails a test (§11).

Mutation proofs (each reverts one correction in a scratch copy of the head, whole where its layers are redundant, and
the named tests must fail): 19 at `e41ce912` (18 killed; M12 survived and gained a view-only test), 31 at `ea2578de` (31
killed after the first M28, which did not compile, was corrected — a compile failure is not a kill), 45 at `01c581f2`
(44 killed; M34 survived because `_bind` is a second layer, and was redefined to revert every layer), 48 at `147f12c6`
(48 killed), 51 at `779925f5` (51 killed), and 52 at `6a92bfc3`: 52 killed, 0 survived. Not every correction has a proof
of its own: M28 reverts only the store layer of closing check 1's leg-overwrite correction, whose `_applyLeg` guard has
none, and a few hygiene and doc corrections have none (the evidence's dispositions list them).

### 14.3 Review dispositions

- Delta review: F1 (HIGH: a LIVE till fell back to the hand-recorded Card while the posture was unknown), F2 – F4
  (MEDIUM) and F5 – F11 (LOW) were fixed, except two minor points of F11 kept by decision (a retry after a 401 under
  the same PIN session; the posture read added to a hand-recorded Card send).
- Closing check 1: two MEDIUM findings — a `permission_denied` status counted as the context proof; a posture proven
  earlier in the PIN session trusted without a re-read — were fixed, and so were the LOW findings but one. A third
  MEDIUM finding, raised by two lenses (the hand-recorded Card is held on any till whose posture cannot be read), and
  that one LOW finding (a stop that is not the attempt's own holds the order in reconciliation) are owner decisions
  (§14.4).
- Closing check 2: the MEDIUM findings — every send-time posture read refreshed the shared PIN-session capabilities,
  so one failed probe hid edit, table, menu and kitchen actions till-wide; the settle-window wait was not bound to the
  send it measured — and four LOW findings were fixed.
- Closing check 3: no defect in the posture and rebuild lenses; the window lens's finding (a wait could time a later
  send with an equal stamp) was graded LOW by its refuter, since it needs two live controllers and a clock that
  repeats an instant, and was fixed anyway (a stamp of its own for every send); its doc finding was fixed. Of the test
  gaps the lenses found, the fresh posture's PIN-session lapse and guard gained a test, the two-controller wait test
  now runs on a clock that stands still, and the binding layers are proven together; the rest were accepted as
  defence in depth or untestable by construction (the evidence lists each).
- Closing check 4: no defect in the code; two LOW findings about what the tests pin (a test whose premise the unique
  stamps had changed, retitled; no test of the exchange-end wait's stamp, added) and two unpinned branches of the
  stamp, now pinned — all tests only (`779925f5`), each proven by a mutation.
- The accuracy check of this packet (two agents, before `1a63a4c0`): ten LOW inaccuracies, all corrected in this
  text; one was a gap between the decoder and §5.2 (a refusal hint stored without a leg was accepted), closed in code
  (`fa12762e`, M54).

### 14.4 Owner decision points

1. The hand-recorded Card is held on ANY till while the posture cannot be read (§9.1): the LIVE outage rule of
   authorization §9 against "other tills byte for byte". The alternative is to remember the last proven posture per
   scope durably.
2. A conflict, mode or amount mismatch, or TEST-identity stop holds the order on this till (reconciliation, no in-app
   exit) until operator tooling exists.
3. A retry after a 401 under the same PIN session is allowed; the server decides.
4. A TEST attempt is out of sight once the lab toggle resets (a PIN-session change); it claims no order and records
   nothing.
   *Corrected 2026-10-31 (correction packet §4.3, §4.4): an unresolved TEST attempt covers its order's tender form on
   this till whatever the lab toggle (a PIN-session change, a restart or a reopened sheet included), with no way back
   and no set-aside until it is final or proven to have no claim; a final TEST result is out of sight with the lab off,
   except one the sheet showed before it turned final, until it is left; a TEST attempt in reconciliation covers its
   order on this till as item 2 says. One whose order is settled elsewhere or voided is out of sight for good, and
   one whose order is fully comped until the order becomes payable again; one that holds server facts and whose
   server row was purged stays shown while its order is payable but can never become final, and holds that order
   on this till; all three stay in the journal — owner point D8 of the correction packet.*
5. A recording leg that returns after a PIN-session switch shows "recorded" to the new session but arms no automatic
   receipt there; Reprint remains.
6. A retry whose card view went away while its posture was read sends nothing ("not sent"); the cashier sends it again
   from the view.
7. The payment sheet's existing tender form (its title and amount rows, which this ticket does not change) overflows a
   390 px phone in every language, measured identical with the posture absent (the feature off) and LIVE; outside this
   ticket.

### 14.5 Not validated

- No device, web or emulator run: widget and unit tests only. No real Edge, provider, terminal or card.
- The window also relies on the Edge creating the claim, if at all, within the request's lifetime (the 001D / 001E
  design); a database call the Edge has abandoned committing later is outside what this ticket can test.
- The platform's 150 s request idle timeout is taken from its documentation and the 001E timing budget, not measured.
- The monotonic clock may stop while an Android device sleeps; that only lengthens the window. Not measured.
- Bytes an operating system still delivers after the app process died (an orphaned connection's retransmissions) are
  bounded by the platform, not by the 001C deadline.
- Two live controllers over one journal are not shipped and are covered only as far as the tests build them. Two
  browser tabs of the hosted POS on one device would hold two (each tab keeps its own `shared_preferences` cache,
  which this journal, like the base payment store, never reloads), but the card transport refuses every card request
  on the web (001C: native only), so no card request leaves either tab.
- The AR / HE strings were checked for presence, direction and layout, not by a native speaker.

### 14.6 Disclosures

- Early in the work one `flutter test` run without `--no-pub` ran an implicit `pub get`; `pubspec.lock` stayed
  byte-identical and every later run used `--no-pub`.
- A temporary file written outside the evidence store during a test diagnosis was moved into the session scratchpad,
  and an evidence folder first created inside the worktree was moved out before any commit; neither entered Git.
- The shared scratch folder at the drive root (`tmp`): the 43 `c001*` items of the completed 001C review were moved to
  the Windows Recycle Bin (recoverable) and listed in the evidence; nothing else there was touched.
- During the round-2 corrections a manifest restore that followed a failed step of the same command ran in the tool's
  default working directory, the repository's main checkout, and overwrote that checkout's root `pubspec.yaml` (the
  pub workspace manifest) with the l10n package's manifest (2026-10-30, 16:56 UTC). The postflight found it (the main
  checkout's tracked changes had gone from 0 to 1); the committed file was restored at 20:05 UTC, after which the main
  checkout has no tracked change and the editor re-resolved its packages with `pubspec.lock` unchanged. This branch
  never carried the error. The evidence's `housekeeping/MAIN_CHECKOUT_PUBSPEC_INCIDENT.txt` has the details.
