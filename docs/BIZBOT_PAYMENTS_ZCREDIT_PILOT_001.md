# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001 — card-present POS payments pilot (Z-Credit PIN pad)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001` (umbrella; tickets 001A–001H below — 001G-DASHBOARD-VERIFICATION and 001H-PILOT-OPS approved by the owner on 2026-10-21 — plus the independent follow-ups `BIZBOT-PAYMENTS-ZCREDIT-HYGIENE-001` and `DASHBOARD-COLLECTED-LABEL-001`).
Decisions: **DECISION D-051** (scope, architecture, gates), **D-052** (lifecycle, identity, money, data), **D-053** (operational, device, credential, recovery and retention policy — the owner decisions of 2026-10-21) **D-054** (the recording-recovery exception — 2026-10-22) **D-055** (the frozen shift / drawer context, the shift-close exclusion and the canonical lock order — 2026-10-22) **D-056** (the correction round 4 owner decisions — 2026-10-22) and **D-057** (the correction round 5 owner decisions — 2026-10-23).
Open questions: **Q-047..Q-050** and **Q-052** (Q-051 and Q-053..Q-057 are resolved by **D-053**). Base of this packet: `origin/main` `e9aec540` (merge of PR #359, 2026-10-21); the branches were synchronized with `main` `ec134ded` (PRs #361 / #364) on 2026-10-22.
Evidence (outside git): the read-only handoff and preflight folders under the owner's `evidence/` root.

This packet records the owner's decisions and the implementation plan. It contains **no** credential,
terminal number, PIN-pad identifier, serial, card number or provider payload, and never will.

## 1. Owner decisions (command-room override, 2026-10-21)

1. The pilot proceeds from the official vendor materials already received plus test-driven discovery;
   further vendor correspondence is **not** a prerequisite for software implementation.
   *(Amended 2026-10-23, round 6: discovery happens only inside the owner-sealed non-settling TEST
   facility of item 9; it never establishes whether a charge settles.)*
2. The override weakens **no** financial or security control.
3. H0 sensitive-material housekeeping is mandatory before any branch (done locally on 2026-10-21:
   the vendor material was moved out of the repository tree with a hash manifest and a local-only
   exclude; no tracked change).
4. 001A docs/design (this packet, D-051, D-052) is mandatory before product code.
5. Architecture: initiate-and-poll with a private provider-attempt ledger (D-051 point 2).
6. The provider base URL, terminal binding, PIN-pad identifier and credentials are runtime
   configuration; never hard-coded or guessed in source.
7. Code may be completed and tested with fakes before any provider call.
8. No Z-Credit call, card use, terminal operation, hosted secret write, migration, deployment or live
   enablement without a separate owner approval after code review.
9. First physical test = TEST mode only (§5), and only after the owner seals the evidence that identifies
   the exact non-settling TEST facility (D-051 point 7, **Q-047**); before it, no real provider action of
   any kind (no provider call, test-card use, terminal payment action or hosted provider-secret setup).
10. Fail closed on any mismatch between device, provider and the received contract; report the exact
    sanitized mismatch; vendor support contact is a targeted escalation and the route to the item-9
    evidence package — whose absence is a hard owner gate, never resolved by a first charge.
11. Never expose PAN, CVV, test-card numbers, PINs, serials, MAC/IMEI values, provider passwords or
    keys, terminal credentials or unrestricted provider payloads.
12. Storefront/Codex work stays fully reserved and untouched.

Owner decisions at the command-room PR review of 2026-10-21, recorded as **DECISION D-053**: (a) a provider
approval whose recording is pending is recovered only by re-recording the same identity on the original
order — never re-charged, never moved, never freed by a manager; an approval that can no longer be legally
recorded is `orphan_approved` and keeps the order blocked for every tender, void, edit, discount and new
attempt until a documented provider void or refund (a standing charge stays an open incident; an
`order_freed` orphan's freed order is never re-blocked, **D-056** point 3); a same-day provider void is
manual and outside BIZBOT, only after explicit owner approval; no automatic void, refund or
release; an `unknown` / `released` attempt is freed only by the manager's `free_order` after documented
provider evidence (`provider_report` / `provider_back_office`) that no approved charge exists, and poll-cap
exhaustion, a provider outage or any self-attestation never frees an order; a memoized recoverable
refusal of the recording leg is re-dispatched only through the **D-054** explicit manager Resume recording; (b) while a claim is active the server refuses every competing tender, discount, edit and void
(`app.card_claim_guard` in `app.sync_push`; `app.record_payment`'s body unchanged); (c) the live Supabase
organization is PRO — the design still never relies on the paid wall clock; (d) TEST traces live only in the
private ledger, sanitized, 90-day retention with an incident hold and an operator-only audited purge; (e) each
restaurant is the merchant of record; TEST credentials are development-only; LIVE credentials per restaurant
by opaque `credential_ref`; no shared LIVE credential; (f) one designated Android POS device, exact-device
mapping, no branch default, local toggle UX only; (g) on a LIVE terminal-enabled till the legacy hand-recorded
card tender is hidden and refused server-side (`card_terminal_required`); (h) the terminal slip and the BIZBOT
receipt are separate documents, no printing change, the receipt is never claimed to be a tax invoice, and an
accountant's confirmation precedes the first LIVE charge (Q-052 stays open); (i) every app-role-callable
ledger mutation is service-only behind the Edge context proof (the operator-only set has no app-role
grant); (j) the Work IDs 001G-DASHBOARD-VERIFICATION, 001H-PILOT-OPS,
`BIZBOT-PAYMENTS-ZCREDIT-HYGIENE-001` and `DASHBOARD-COLLECTED-LABEL-001` are approved. Final independent
review round 3 (2026-10-22, **D-055**): (k) a LIVE attempt freezes the device's OPEN shift, its ACTIVE drawer
session and the proven initiator at the claim; the recording leg and every Resume are admitted only inside
that frozen context (a new shift or drawer never absorbs an approval; a lost context is `orphan_approved`);
`shift.close` is refused `card_payment_in_progress` while an attempt frozen to the shift is unresolved; one
canonical lock order; the owner read projects the frozen context and actors; the vendor's free-text return
message is never persisted (a normalized return class is).
Correction round 4 (2026-10-22, **D-056**): (l) a charge is never started on an order already settled by any
tender (`order_already_settled` under the order lock, zero provider calls); (m) a recording refused
`permission_denied` or `revoked_employee` is resumed by a manager on the same till with no reinstatement,
`revoked_device` never; (n) a provider anomaly (`charge_may_exist`) is never freed by a manager; (o) the
provider-fact writer is scope-bound; (p) operator actions are private events with a verified operator actor,
and writing-RPC TEST denials and security mismatches are private events too; (q) TEST writes zero tenant
audit rows and is projected `test_<state>`; (r) every later provider call re-validates the attempt's own
credential records; (s) card-sensitive operations travel one per `sync_push` call and a transient database
failure is never memoized; (t) the required
`max_live_amount_minor`, the inbound amount grammar, the per-attempt poll cap and the text UUID v4 identity.
Correction round 5 (2026-10-23, **D-057**): (u) a provider identity is recordable only as its own admissible
LIVE leg — a TEST identity never — and `recorded` is a strict join of identity, order, method, amount,
currency and the frozen shift and drawer; (v) the recording leg omits `expected_revision` through a
provider-leg sibling record (PDR-003 unchanged for every other tender); (w) the manager Resume re-proves an
active manager and its evidence is bounded; (x) the till binding is written only by the operator RPC
`app.set_payment_terminal`, with the `configured → enabled → draining → retired` lifecycle and one
`enabled` / `draining` till per organization; (y) only a fresh claim makes the provider commit call;
(z) operator actions name an attested owner approver and record the executor; plus the minor corrections of
**D-057** point 8 (TEST minimisation, the fail-closed TEST cap, sticky revocation, the transient classes,
safe free text and the LIVE activation gates).

Sequencing: H0 → 001A → 001B → 001D → 001E → 001C (as required) → 001F → deploy with all flags OFF →
owner-approved TEST secret setup → owner-approved QD3 test-card run → evidence review → later
production Maps Burger pilot approval. Reports list only concrete code, configuration, deployment or
physical-test blockers.

## 2. Baseline facts the design rests on (verified read-only, 2026-10-21)

- `app.record_payment` is reachable only through `public.sync_push` → `payment.create`; it requires a
  valid PIN session, an active device session and a device match, an OPEN shift and an ACTIVE drawer
  for every tender, locks the order, replays idempotently on `device_id + local_operation_id`, allows
  one completed payment per order and writes only `status='completed'`; non-cash rows carry
  `amount_minor = tendered_minor = grand_total_minor`, `change_minor = 0`. No UPDATE/DELETE path on
  `payments`; no void or refund RPC exists (API §4.7a `void_payment` is unimplemented contract text; its wording is reconciled in 001B).
- The POS already freezes one durable payment attempt before the first send (persist-before-send,
  single-flight, same bytes on every resend of the baseline attempt — the **D-054** Resume recording adds only the fingerprint-excluded
  `recording_resume` envelope key, API §4.55.7 —, explicit Resume / Check status, no automatic retry).
- The POS transport timeout is a 15 s constructor default shared by every RPC and Edge call and is
  not per-call configurable. Supabase Edge limits: 150 s request idle timeout (504), wall clock 150 s
  (Free) / 400 s (paid), 2 s CPU. The live organization was verified as PRO by the owner on 2026-10-21
  (**D-053** point 3); the design still bounds the start deadline by the 150 s idle timeout and never relies
  on the wall clock. A background continuation runs only within the wall clock.
- The Dashboard classifies `method='card'` correctly on the intended tender surfaces and every total
  reads `status='completed'` only. The all-tender "Cash collected" label and the sales-summary fallback
  are separate defects of `DASHBOARD-COLLECTED-LABEL-001` (001G verifies the card surfaces; **D-056**
  point 11), whose deployment — or the owner's recorded acceptance of the mislabel — gates LIVE
  enablement (DEPLOYMENT §18.1 step 9; **D-057** point 8); the pilot's only Dashboard change is the
  exact [MVP_SCOPE](MVP_SCOPE.md) §5 exception — 001D's §4.33 audit registry, labels and titles and
  001G's tests, limited to the files of §7 (amended 2026-10-23, round 6).
- No payment-provider secret, table or code exists on `main` or on the hosted project.

## 3. Provider contract map (Z-Credit WebService, public documentation; sanitized)

| Topic | Contract fact used by the design |
|---|---|
| Transport | Server-to-server JSON over TLS 1.2; terminal credentials in every request body; no webhook or callback; no IP allow-list documented. |
| Environment | One production base URL is published; the test environment, test terminal and test cards come from the vendor (runtime configuration, **Q-047**). |
| Addressing | The PIN pad is selected by a device identifier carried in the track field with the card fields empty; no documented API binds a pad to a terminal — the association is presumed to be a vendor back-office setting (INFERENCE, **Q-050**). |
| Sale | A single commit call with amount, currency type, charge type and customer-present flag fixed before the pad prompts; the synchronous reply "can take several minutes"; only the API reply confirms a transaction. |
| Amount | Decimal major units with two decimals (not minor units); the commit reply echoes no amount; status lookups echo the amount and currency type. |
| Correlation | Two merchant-supplied keys: a status-recovery key (queried back by the status-by-unique-id lookup) and an exact-match duplicate-check key (exact repeat refused with a dedicated code). An advanced card-hash variant exists and is not used. |
| Reply | Error flag, return code, message, provider reference, approval and voucher numbers, approval type (approved / declined variants), phone-authorization flag, card fields (full or masked by a terminal setting), last four, brand, token, receipt texts, raw processor records, entry mode, payment method, tip amount. |
| Status lookup | By provider reference or by the merchant key; status codes for approved-not-deposited (voidable), approved-deposited (refundable), voided, refunded, partially refunded and pre-authorization states; no "declined" code (**Q-048**). |
| Release | Cancels a pending pad transaction only while the pad shows its swipe screen; advisory for the design. |
| Void / refund | One call by provider reference, full or partial; before deposit = void, after = refund. **Not called by the application in the pilot** (D-052 point 5). |

## 4. Architecture (DECISION D-051 point 2; detailed contract in 001B)

| Component | Ticket | Shape |
|---|---|---|
| Private provider-attempt ledger (`app` schema) | 001D | tenant columns (`organization_id`, `restaurant_id`, `branch_id`, `device_id`), optional `order_id` (NULL in TEST mode), the frozen `shift_id` / `cash_drawer_session_id` (NULL in TEST mode) and initiating employee and membership (frozen in both modes) of **D-055**, `provider_approved_at`, `local_operation_id`, mode `test` / `live`, state (`sent` / `approved` / `declined` / `unknown` / `released`; `recorded`, `approved_unrecorded` and `orphan_approved` are derived; `released` is provisional until a status lookup), both full internal key digests and both provider keys as sent (D-052 point 2), `amount_minor` + `currency_code`, allowlisted, field-validated provider codes only (the numeric return code and a normalized return class; no provider free text), lookup / poll / release / recording / resume-history / resolution / hold metadata, `retention_until` (TEST rows only), timestamps; UNIQUE (`organization_id`, `device_id`, `local_operation_id`); partial UNIQUE on `order_id` while claimed (incl. approved-unrecorded); `provider_anomaly_code` / `charge_may_exist` (**D-056** point 3); a text `local_operation_id` with a UUID v4 CHECK; forced RLS, deny policies, no app-role grants; no phase-1 application role, RPC or the TEST purge deletes a LIVE row (final legal retention per D-013 / Q-005), TEST rows purged only by the operator-only purge after 90 days; plus the exact-device PIN-pad mapping table (opaque `terminal_ref` + `credential_ref`, `mode`, the `configured → enabled → draining → retired` lifecycle, one device per row and one current (non-`retired`) row per device, at most one `enabled` / `draining` row per organization, one LIVE `credential_ref` per restaurant (the TEST `credential_ref` development-scoped and owned by none), no branch default; written only through the operator-only `app.set_payment_terminal` by the owner-approved 001H procedures — the `test` row at TEST secret setup, retired after the TEST run, then a new `live` row at production enablement, **D-057** point 4); plus the private operator / security event table `app.card_provider_private_events` (forced RLS, no grants, never projected, **D-056** point 5). |
| Ledger RPCs | 001D | a read-only context proof for `authenticated` (pattern `app.pos_web_order_context`: VOLATILE, its device-session renewal the only write — no ledger, audit or private-event row); service-only claim / adapter-read / finish / mark-release-requested / mark-recording-result (`service_role` on both layers; the claim, and the adapter read for a `sent` / `unknown` / `released` attempt, re-validate the passed credential and terminal maps in SQL and write the private security event on a mismatch, **D-056** point 7; each re-running the proof at write time except `card_attempt_finish`, which is scope-bound to the row id, organization, device, identity, mode, amount and currency of the same request, **D-056** point 4); the manager `free_order` bounded by the provider-evidence confirmation; `app.card_claim_guard` called by `app.sync_push` in the six arms of API §4.55.3 (typed `payment_in_progress` / `amount_mismatch` / `card_terminal_required` / `card_context_lost`, the identity-first provider recording gate with `test_attempt_not_recordable` / `provider_recording_refused` — **D-057** point 1 — and `card_payment_in_progress` for `shift.close` — **D-055**; `app.record_payment` body unchanged) and `app.card_recording_resume_guard` in its valid-device ledger-claim step (the **D-054** reopen of a memoized recoverable refusal — `precondition_failed` / `revoked_employee` / `permission_denied` — once per Resume under the active-manager proof, a history entry per authorized dispatch, at most three — **D-057** point 3); the paid-order pre-call guard inside the claim (**D-056** point 1); the claim returning `claim_created` / `replayed` (**D-057** point 5); operator-only revision setter (with the required `max_live_amount_minor` and a positive `max_test_amount_minor`), terminal binding `app.set_payment_terminal` (**D-057** point 4), orphan / anomaly resolution and the TEST closure `test_closed` (**D-057** point 4), TEST incident hold (`app.card_attempt_set_incident_hold`) and TEST purge, each with an attested owner approver, the recorded executor principal and a private event (**D-057** point 6); typed RETURN envelopes with a scalar `detail` (each guard refusal also with `server_ts` and the payload `order_id`, or `shift_id` for `shift.close`, **D-057**); the Activity-log functions re-created for the `card_attempt.*` family only (API §4.33). |
| Edge provider adapter (proposed `pos-card-charge`) | 001E | caller JWT on a caller-scoped client for the context proof and `free_order`; a service-role client, held in the ledger module only, for the service-only mutations after a successful proof; exact key set; `start` (proof → claim → provider commit — only when the claim answered `claim_created`, never on a replay or a concurrent loser, **D-057** point 5 — under a bounded deadline → ledger outcome; expiry = UNKNOWN), `status` (proof → adapter read → provider lookup → ledger), `release` (advisory); reads only documented NAMES through an injected, shape-validated accessor pinned by a static guard; never logs bodies; float-free money module with the inbound amount grammar; the canonical UUID v4 `attempt_id` check; the configuration maps passed to the adapter read on every `status` / `release`, with no provider request on its `provider_unavailable` (the SQL re-validates the attempt's frozen references, **D-056** point 7); scope-bound finish arguments taken only from the same request's claim or adapter read. |
| Runtime configuration | 001H (values) / 001D (table) | master flag (exact `true`) and one provider configuration secret (JSON: environment, base URL, mode- and scope-aware credential records keyed by opaque `credential_ref` — the TEST record development-scoped and owned by no restaurant, LIVE records per restaurant — and PIN-pad identifiers keyed by opaque `terminal_ref`), the TEST record installed at the owner-approved TEST secret setup (`environment=test`) and a restaurant's LIVE record only at the separately approved production enablement (DEPLOYMENT §18.1 step 9); the exact-device mapping table that holds only opaque references ships with the 001D migration; the designated device's UUID is recorded only in the 001H evidence outside git, never in the repository. |
| Shared transport capability | 001C | new capability interface in `packages/data_remote` with its own timeout, implemented by the Supabase, upgradable and guarded transports (`packages/auth_identity`). |
| POS Payment Lab | 001F | decorator on `PaymentAttemptSender` for the provider leg plus a provider-approved recording path (**D-057** point 2): the existing 26-key base `PaymentAttempt` schema stays as it is and a separately versioned provider-leg sibling record holds the canonical recording operation, persisted before its first send and serialized without `expected_revision` — the one provider-leg exception to PDR-003, every other tender keeping it — and reused by the first send, every resend, restart recovery and the **D-054** Resume; polling; outcomes `providerDeclined`, charged-unrecorded, provider status unavailable; per-device default-OFF lab screen (UX only); the legacy `card` tender hidden on a LIVE terminal till (`card_terminal_mode='live'`: its mapping `configured`, `enabled` or `draining`); the seven typed refusals of API §4.35 item 4 (`payment_in_progress`, `test_attempt_not_recordable`, `provider_recording_refused`, `amount_mismatch`, `card_terminal_required`, `card_context_lost`, `card_payment_in_progress`); `method='card'` unchanged; `order_action_row.dart` untouched. |
| Dashboard | 001G / 001D | 001G: verification tests only; 001D: the `card_attempt.*` audit registry entries, safe-detail labels and ar / he / en titles only — the one [MVP_SCOPE](MVP_SCOPE.md) §5 exception, in the files of §7. |

## 5. TEST-mode protocol (first physical test; D-051 point 4)

- Gate (hard; D-051 point 7, **Q-047**, amended 2026-10-23): nothing below runs — no provider commit,
  status or release call, no test-card use, no terminal payment action, no hosted provider-secret
  setup — until the owner has sealed, outside Git, the evidence that identifies the exact non-settling
  TEST facility: the test base URL / environment; the test credential record with its mode and scope;
  the test terminal / PIN-pad binding; the test-card status; written or provider-portal evidence that
  they cannot settle or move real money; the exact key / purpose / environment mapping. A missing or
  failed package stops here; it is never replaced by discovering settlement with a first charge.
- Session: one paired-device / PIN session established before the sealed PRE snapshot and kept for the
  whole run — no sign-out or sign-in, PIN change, shift or drawer transition; a session that expires
  or changes aborts the run.
- Scope: Maps Burger organization / branch; a real paired POS device with a real PIN session and
  membership; the lab screen enabled on that one device only.
- Attempt: order-less (amount-only, small amount, `order_id` NULL); mode `test`; one frozen identity
  minted and persisted before the first provider request; both provider keys derived from its full
  tuple (organization, device, local operation id; D-052 point 2).
- Never: `record_payment`, a `payments` row, a receipt number, a shift or drawer effect, an order-history
  or kitchen change, a Dashboard revenue change, any tenant `audit_events` row — denials included (**D-053**
  point 4, **D-056** point 6; a TEST denial RETURNED by a writing RPC writes only a private event); the
  server refuses any `payment.create` under a TEST identity (`test_attempt_not_recordable`; a defective push of one leaves only the rejected sync row and its generic audit, plus the RPC's own `payment.denied` when it denies the session's role), a TEST attempt
  stores no card or provider-reference data and a TEST revision requires a positive `max_test_amount_minor`
  (**D-057** points 1 and 8); a TEST attempt that no status lookup resolves is closed after the run through
  the operator resolution `test_closed` (**D-057** point 4).
- Transport: UNKNOWN on timeout or dropped connection; no automatic retry; recovery by the status
  lookup under the same identity; an exact-repeat refusal is "already submitted".
- Fail closed: no pad prompt, a credential or environment rejection, or an out-of-contract reply ends
  the attempt UNKNOWN or refused; the run stops; the sanitized mismatch (field names, codes, timings;
  never values) is reported for targeted escalation.
- Evidence: the sealed test report lists attempt identities, states, return codes and timings only.
- Retention: TEST rows carry `retention_until = created_at + 90 days`; an incident hold keeps a row or a
  single TEST private event (**D-057** point 8); the operator-only purge deletes only expired, unheld TEST
  rows and every `mode='test'` private event past its own `retention_until` that is itself unheld and whose
  attempt, if any, is unheld (never an `operator.*` event); no phase-1 application role, RPC or the TEST purge deletes LIVE evidence (final
  legal retention per **D-013** / **Q-005**; **D-053** point 4).

## 6. Money and data rules (D-052 points 4 and 6)

- Integer minor units everywhere; the adapter's canonical two-decimal lexeme, emitted as an unquoted JSON
  number token by a validated raw-number serializer (never a float, `Number`, `parseFloat`, floating-point
  arithmetic or locale formatter; integer division and modulo of the minor amount are the derivation), is the
  only decimal boundary; inbound amounts accepted only as raw token text matching
  `^(0|[1-9][0-9]{0,8})\.[0-9]{2}$`, converted by integer arithmetic (anything else is the `out_of_contract`
  provider anomaly); strict minor-unit equality on lookups; LIVE amounts bounded by the required
  `max_live_amount_minor` (**D-056** point 9); currency must match the order currency (ILS for the
  pilot tenant); the tip object is omitted on the request, and a commit approval requires a tip absent or
  exactly zero — a non-zero tip is the anomaly `amount_mismatch`, an unreadable one `out_of_contract`
  (**D-057** point 8).
- Persist only closed classes and validated codes (LIVE attempts; a TEST attempt keeps none of the card or
  provider-reference fields, **D-057** point 8): provider reference, approval number, voucher number, last
  four digits, brand code, approval type, the integer return code and a normalized return class, entry
  mode, payment method, status code, deposit id, provider timestamp, minor amounts with currency — each
  after its field-specific character-set / length rule and the no-card-data rule (a failing field is
  dropped). The vendor's free-text message is inspected transiently and dropped; no provider free text is
  ever stored, logged, audited or returned (amended 2026-10-23, round 6).
- Never persist, log, print or display: full or masked card number, BIN, expiry, token, raw or
  encrypted processor records, receipt texts, request bodies, any field outside the allowlist.

## 7. Scope allowlist and forbidden paths

- Allowed by ticket: 001A/001B docs; 001C `packages/data_remote`, `packages/auth_identity`,
  `packages/l10n` ARBs; 001D one forward-only migration (including the single re-creation of `app.sync_push` with exactly four changes — the claim-guard call in its six existing arms (the five money arms plus `shift.close`, **D-055**), the **D-054** recording-reopen step (carrying the protected `recording_resume` parse in the valid-device per-operation preamble (refusing a non-empty `depends_on` beside the key) and the `resume_authority_required` check in the ledger-claim step's adopt branch, **D-057** point 3), and the **D-056** card-sensitive single-operation check and transient classification — and the private event table) + pgTAP plus the Dashboard `kAuditActionRegistry` entries, `_displayableKeys` labels and ar / he / en audit titles under the ORDER-EDIT-001A owner-approved exception pattern (API §4.33) — the one Dashboard exception of [MVP_SCOPE](MVP_SCOPE.md) §5, limited to exactly `apps/dashboard/lib/src/data/audit_action_registry.dart`, `apps/dashboard/lib/src/data/audit_log_presentation.dart`, `packages/l10n/lib/l10n/app_en.arb`, `app_ar.arb`, `app_he.arb`, the `packages/l10n/lib/src/generated/app_localizations*.dart` files regenerated from those ARBs, and the rendering test `apps/dashboard/test/card_attempt_activity_log_test.dart` (§4.33), with no analytics or report change (**D-057** point 8) — and the re-creation of `app.pin_session_capabilities` / `app.pos_order_snapshots` for their additive keys only (PRE / POST source, hash and ACL, DEPLOYMENT §18.2); 001E one new function directory, an
  additive `config.toml` block and one explicit CI test step; 001F `apps/pos` payment files listed in
  the preflight (the provider-approved recording path and the provider-leg sibling record; the 26-key base
  `PaymentAttempt` schema and PDR-003 for non-provider tenders unchanged, **D-057** point 2) and the refusal
  classifiers the seven guard codes reach — `order_edit_response.dart`, `addition_controller.dart`,
  `void_repository.dart`, `discount_repository.dart` and `shift_repository.dart` under `apps/pos/lib/src`
  (API §4.35 item 4); 001G tests only.
- Forbidden: `storefront/**`, `supabase/functions/web-order-submit/**`,
  `supabase/functions/pos-web-order-decision/**` (precedent only), `supabase/functions/storefront-media-publish/**`,
  `supabase/functions/_shared/**`, Storefront / web-order migrations and docs, the `bizbot-storefront`
  Vercel project, any unregistered Codex location; `apps/pos/lib/src/widgets/order_action_row.dart`
  (PR #314), `packages/printing/**` and the receipt preview (PR #315) in phase 1;
  `tools/android_release/**`, `docs/ANDROID_RELEASE_SIGNING.md`, `tools/vercel/ignore-build.mjs`,
  lockfiles and generated files (except the l10n localizations regenerated for the 001D Dashboard exception
  above); the body of `app.record_payment`; the D-018 enumerations; the
  dirty `BIZBOT-INSTANT-NOTIFICATION-WAKE-001` worktree.
- Base and order: every ticket branches from a fresh `origin/main`; #314 and #315 do not block
  001A–001E; merge or close them before 001F.

## 8. Validation and rollout gates

| Gate | Proof |
|---|---|
| Unit / integration (fakes) | float-free money; the full-identity key digests deterministic and domain-separated (status vs duplicate), never from `local_operation_id` alone (D-052 point 2); journal sibling-key round trip and older-build quarantine; gate fail-closed; approved / declined / UNKNOWN / released paths; Resume never re-charges; a second till's `start` refusal rendered typed with no retried start; restart mid-attempt recovers; the legacy `card` tender hidden on a LIVE terminal till (`card_terminal_mode='live'`: its mapping `configured`, `enabled` or `draining`); the seven typed refusals of API §4.35 item 4; the provider-leg sibling record serialized without `expected_revision` and reused byte-identically by every send, restart and Resume while non-provider tenders keep PDR-003; a never-delivered leg resent by an active cashier+ on the same till; `resume_authority_required` resent only under a manager session (**D-057**); card-sensitive operations pushed one per call, a `single_operation_required` answered by resending each operation alone and a `transient_failure` resent under the same identity; the manager Resume of a `permission_denied` / `revoked_employee` recording; a provider anomaly never freeable; TEST attempts shown as `test_<state>`; ar / he / en. |
| Shared transport | both boot compositions forward the capability; blocked session refuses; late response after timeout causes no second transmission; dedicated timeout independent of the 15 s default. |
| Edge adapter | exact environment-read allow-list and `config.toml` pin; JWT forwarding; closed-set projection; timeout → UNKNOWN; no body logging; exact money serialization proven on the outbound request bytes (0.01, 1.00, 12.34, the configured maximum TEST amount, the configured `max_live_amount_minor`) with a static guard against float, `Number`, `parseFloat`, floating-point arithmetic or locale formatting on money (integer division and modulo of the minor amount are permitted); the configuration maps passed to the claim and, on every `status` / `release`, to `card_attempt_adapter_read`, with zero provider requests on their `card_payments_disabled` / `provider_unavailable` (the SQL checks and their security events are 001D, T-023 pgTAP); the canonical UUID v4 `attempt_id` check; the inbound amount grammar; scope-bound finish arguments (**D-056**); exactly one commit call for a claim answered `claim_created` and zero on a replay or a concurrent loser, the tip rule and a late commit reply finishing nothing (**D-057**); outbound keys only from the sealed formatter configuration — without it `provider_unavailable` and zero provider calls (**Q-049**); the vendor's free-text message never stored, logged or returned. |
| T-023 (pgTAP + the Edge test lane + static guard) | role denies, forced RLS, immutability, no provider free-text column, field-validated provider codes, proof-derived tenant context, the enumerated `authenticated` grants (context proof, `free_order`, owner read) and every service-only pair refused to `authenticated`, the `app.sync_push` guard (competing operations refused on a claimed order, a provider identity recorded once and only as its own admissible LIVE leg, hand-recorded `card` refused on a till whose LIVE mapping is `configured`, `enabled` or `draining`, other devices unchanged, `app.record_payment` hash unchanged), `free_order` evidence-bound (`provider_report` / `provider_back_office` only) and never for an approved attempt, a standing charge never freed, the **D-054** Resume-recording carve-out (replay-forever for every ordinary row, one re-dispatch for a provider-approved recoverable refusal, `expected_revision` omitted and recorded after a revision move, cap, count binding and concurrency, unchanged provider state), the **D-055** binding (frozen shift / drawer / initiator from the proof, `shift.close` refused while an attempt frozen to the shift is unresolved and allowed after declined / recorded / provider-voided / refunded, no other shift or drawer records the approval, a Resume cannot switch context, concurrent claim or Resume versus shift close serial and deterministic, lock-order stress with no deadlock, TEST never blocks a shift, no free-text provider message column), exact-device mapping with mode-aware credential records (LIVE bound to one restaurant, TEST owned by none), TEST mode never writes `payments` / receipt / shift / order history / Activity log and is purged only after retention, one in-progress attempt per order, kitchen exclusion, accountant read-only, support mode denied; the adapter makes no service-only call before a successful proof; and the **D-056** cases — the paid-order pre-call guard with zero provider calls, the `permission_denied` Resume and `revoked_device` never resumable, the provider anomaly, the scope-bound finish, operator actors and private events, zero tenant audit for TEST, credential revalidation, the single-operation batch, the transient resend, role before attempt details, and the grants of every function and table enumerated for `anon` / `authenticated` / `service_role`; and the **D-057** cases — the identity-first zero-payment cases and the strict `recorded` join, the active-manager Resume proof and bounded evidence, the `recording_resume` scope and protected parse, the terminal binding with its lifecycle and one-device constraint, claim freshness, authorization before disclosure, the recording-result proof, finish after resolution, sticky revocation, TEST minimisation and the fail-closed TEST cap, the safe-text helper and the READ COMMITTED settled check; lane labels: pgTAP proves database conditions, the Edge fake-provider lane provider-call counts, the Dart lane UI and transport. |
| Deploy (001H) | migration PRE/POST per OPERATIONS §4.2 and DEPLOYMENT §18.2 (patterned on §17.2), with the source, hash and ACL of every re-created function; function deployed with every flag OFF; secret NAMES verified, values never read back, and no provider secret installed before the sealed **Q-047** and **Q-049** evidence; the terminal binding only through `app.set_payment_terminal`; the LIVE activation gate of DEPLOYMENT §18.1 step 9 (**Q-048** resolved or its interim accepted, `DASHBOARD-COLLECTED-LABEL-001` deployed or the owner's acceptance, a clean till, the exact reviewed build, a known shift state, sealed evidence); the read-only Card Attempts incident view of 001H as the `owner_card_attempts` consumer — a documented read-only query an in-scope owner, manager or accountant runs in their own session, no new app surface (**D-057**). |
| Physical test (001H) | only after the sealed non-settling TEST facility evidence (§5 gate, **Q-047**); TEST mode per §5 only, owner present, one session kept for the whole run; hosted PRE/POST queries prove no Maps Burger production row changed. |
| Rollback | master flag OFF → operator revision OFF → per-device toggles OFF, or one till's mapping `enabled → draining` (status reads and recording keep working so in-flight attempts resolve; no environment switch and no direct table edit, **D-057**); keep every ledger row; no replay; forward-only migrations. |

PR sequencing (**D-056** point 11): #362 merges first and #363 right after its own final approval; merging #362 alone temporarily exposes the earlier design wording, and the stacked review order is never skipped. The 001D exact-scope authorization is tied to the eventual #363 merge commit, never to #362 alone (**D-057** point 8).

## 9. Owner decisions still open and targeted escalation list

Owner decisions recorded on 2026-10-21 as **DECISION D-053** (the correction round 4 decisions of 2026-10-22 are **DECISION D-056**, the correction round 5 decisions of 2026-10-23 **DECISION D-057**): Q-051 (orphan approval / same-day void),
Q-053 (plan tier), Q-054 (per-restaurant credentials, merchant of record), Q-055 (TEST-mode traces and
retention), Q-056 (one Android till) and Q-057 (hand-recorded card). Still open: **Q-052** (receipt / tax
document law — the accountant's confirmation is mandatory before the first LIVE charge and blocks nothing in
001D–001F); **Q-047** and **Q-049** — hard owner gates on every real provider action (the sealed non-settling TEST facility evidence and the sealed key-format evidence, **D-051** point 7, amended 2026-10-23), neither blocking code or fake-provider work; and **Q-048** / **Q-050** (discovery only inside the sealed TEST facility; neither blocks 001D–001F; **Q-048** must be resolved, or its interim
explicitly accepted by the command room, before production enablement — **D-057** point 8). **Q-056** is also recorded as
D-051 point 9 (Android POS only, 2026-10-23).

Vendor support is the route to the two gating evidence packages — the exact non-settling TEST
facility (test environment host, credential record and mode, terminal / PIN-pad binding, test-card
status, no-settlement evidence and the purpose of the extra key — **Q-047**) and the key length and
character rules (**Q-049**); without them nothing real runs. Targeted escalation, only if discovery
inside the sealed facility fails or a mismatch appears: status-lookup semantics for never-received /
declined / pending attempts (**Q-048**); the duplicate-check window (**Q-049**); device model,
identifier and the masking setting (**Q-050**); maximum pad blocking time, return codes for pad timeout / offline / busy /
after release, behaviour when the HTTP connection drops mid-call; release-versus-tap race; deposit
timing; tip amount unit; customer-present expectation.
