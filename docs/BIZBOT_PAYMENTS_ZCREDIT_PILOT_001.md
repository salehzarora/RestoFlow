# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001 — card-present POS payments pilot (Z-Credit PIN pad)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001` (umbrella; tickets 001A–001H below — 001G-DASHBOARD-VERIFICATION and 001H-PILOT-OPS approved by the owner on 2026-10-21 — plus the independent follow-ups `BIZBOT-PAYMENTS-ZCREDIT-HYGIENE-001` and `DASHBOARD-COLLECTED-LABEL-001`).
Decisions: **DECISION D-051** (scope, architecture, gates), **D-052** (lifecycle, identity, money, data) and **D-053** (operational, device, credential, recovery and retention policy — the owner decisions of 2026-10-21).
Open questions: **Q-047..Q-050** and **Q-052** (Q-051 and Q-053..Q-057 are resolved by **D-053**). Base of this packet: `origin/main` `e9aec540` (merge of PR #359, 2026-10-21).
Evidence (outside git): the read-only handoff and preflight folders under the owner's `evidence/` root.

This packet records the owner's decisions and the implementation plan. It contains **no** credential,
terminal number, PIN-pad identifier, serial, card number or provider payload, and never will.

## 1. Owner decisions (command-room override, 2026-10-21)

1. The pilot proceeds from the official vendor materials already received plus test-driven discovery;
   further vendor correspondence is **not** a prerequisite for software implementation.
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
9. First physical test = TEST mode only (§5).
10. Fail closed on any mismatch between device, provider and the received contract; report the exact
    sanitized mismatch; support contact becomes a targeted escalation, not a blocker.
11. Never expose PAN, CVV, test-card numbers, PINs, serials, MAC/IMEI values, provider passwords or
    keys, terminal credentials or unrestricted provider payloads.
12. Storefront/Codex work stays fully reserved and untouched.

Owner decisions at the command-room PR review of 2026-10-21, recorded as **DECISION D-053**: (a) a provider
approval whose recording is pending is recovered only by re-recording the same identity on the original
order — never re-charged, never moved, never freed by a manager; an approval that can no longer be legally
recorded is `orphan_approved`, keeps the order blocked and needs owner / operator reconciliation; a same-day
provider void is manual and outside BIZBOT, only after explicit owner approval; no automatic void, refund or
release; an `unknown` / `released` attempt is freed only by the manager's `free_order` after an explicit
provider / back-office confirmation — or a command-room-approved evidence step — that no approved charge
exists, and poll-cap exhaustion alone never frees an order; (b) while a claim is active the server refuses every competing tender, discount, edit and void
(`app.card_claim_guard` in `app.sync_push`; `app.record_payment`'s body unchanged); (c) the live Supabase
organization is PRO — the design still never relies on the paid wall clock; (d) TEST traces live only in the
private ledger, sanitized, 90-day retention with an incident hold and an operator-only audited purge; (e) each
restaurant is the merchant of record; TEST credentials are development-only; LIVE credentials per restaurant
by opaque `credential_ref`; no shared LIVE credential; (f) one designated Android POS device, exact-device
mapping, no branch default, local toggle UX only; (g) on a LIVE terminal-enabled till the legacy hand-recorded
card tender is hidden and refused server-side (`card_terminal_required`); (h) the terminal slip and the BIZBOT
receipt are separate documents, no printing change, the receipt is never claimed to be a tax invoice, and an
accountant's confirmation precedes the first LIVE charge (Q-052 stays open); (i) every ledger mutation is
service-only behind the Edge context proof; (j) the Work IDs 001G-DASHBOARD-VERIFICATION, 001H-PILOT-OPS,
`BIZBOT-PAYMENTS-ZCREDIT-HYGIENE-001` and `DASHBOARD-COLLECTED-LABEL-001` are approved.

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
  single-flight, same bytes on every resend, explicit Resume / Check status, no automatic retry).
- The POS transport timeout is a 15 s constructor default shared by every RPC and Edge call and is
  not per-call configurable. Supabase Edge limits: 150 s request idle timeout (504), wall clock 150 s
  (Free) / 400 s (paid), 2 s CPU. The live organization was verified as PRO by the owner on 2026-10-21
  (**D-053** point 3); the design still bounds the start deadline by the 150 s idle timeout and never relies
  on the wall clock. A background continuation runs only within the wall clock.
- The Dashboard represents `method='card'` correctly on every money surface; every total reads
  `status='completed'` only. No Dashboard change is needed for the agreed row shape.
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
| Private provider-attempt ledger (`app` schema) | 001D | tenant columns (`organization_id`, `restaurant_id`, `branch_id`, `device_id`), optional `order_id` (NULL in TEST mode), `local_operation_id`, mode `test` / `live`, state (`sent` / `approved` / `declined` / `unknown` / `released`; `recorded`, `approved_unrecorded` and `orphan_approved` are derived; `released` is provisional until a status lookup), both provider keys as sent, `amount_minor` + `currency_code`, allowlisted provider fields only, lookup / poll / release / recording / resolution / hold metadata, `retention_until` (TEST rows only), timestamps; UNIQUE (`organization_id`, `device_id`, `local_operation_id`); partial UNIQUE on `order_id` while claimed (incl. approved-unrecorded); forced RLS, deny policies, no app-role grants; LIVE rows never deleted by any role or RPC (retention per D-013 / Q-005), TEST rows purged only by the operator-only audited purge after 90 days; plus the exact-device PIN-pad mapping table (opaque `terminal_ref` + `credential_ref`, `mode`, one device per row, one `credential_ref` per restaurant, no branch default; populated only by the owner-approved 001H procedures — the `test` row at TEST secret setup, the `live` row at production enablement). |
| Ledger RPCs | 001D | a read-only context proof for `authenticated` (pattern `app.pos_web_order_context`); service-only claim / adapter-read / finish / mark-release-requested / mark-recording-result (`service_role` on both layers, each re-running the proof at write time except `card_attempt_finish`, which rechecks only the attempt's own scope, state and amount); the manager `free_order` bounded by the confirmation attestation; `app.card_claim_guard` called by `app.sync_push` in the five arms of API §4.55.3 (typed `payment_in_progress` / `amount_mismatch` / `card_terminal_required`; `app.record_payment` body unchanged); operator-only revision setter, orphan resolution, TEST incident hold (`app.card_attempt_set_incident_hold`) and TEST purge; typed RETURN envelopes. |
| Edge provider adapter (proposed `pos-card-charge`) | 001E | caller JWT on a caller-scoped client for the context proof and `free_order`; a service-role client, held in the ledger module only, for the service-only mutations after a successful proof; exact key set; `start` (proof → claim → provider commit under a bounded deadline → ledger outcome; expiry = UNKNOWN), `status` (proof → adapter read → provider lookup → ledger), `release` (advisory); reads only documented NAMES through an injected, shape-validated accessor pinned by a static guard; never logs bodies; float-free money module. |
| Runtime configuration | 001H (values) / 001D (table) | master flag (exact `true`) and one provider configuration secret (JSON: environment, base URL, per-merchant credential records keyed by opaque `credential_ref` — the TEST record development-only, LIVE records per restaurant — and PIN-pad identifiers keyed by opaque `terminal_ref`), the TEST record installed at the owner-approved TEST secret setup (`environment=test`) and a restaurant's LIVE record only at the separately approved production enablement (DEPLOYMENT §18.1 step 9); the exact-device mapping table that holds only opaque references ships with the 001D migration; the designated device's UUID is recorded only in the 001H evidence outside git, never in the repository. |
| Shared transport capability | 001C | new capability interface in `packages/data_remote` with its own timeout, implemented by the Supabase, upgradable and guarded transports (`packages/auth_identity`). |
| POS Payment Lab | 001F | decorator on `PaymentAttemptSender`; provider-leg sibling journal key; polling; outcomes `providerDeclined`, charged-unrecorded, provider status unavailable; per-device default-OFF lab screen (UX only); the legacy `card` tender hidden on a LIVE terminal-enabled till; typed `payment_in_progress` / `card_terminal_required` refusals; `method='card'` unchanged; `order_action_row.dart` untouched. |
| Dashboard | 001G | verification tests only. |

## 5. TEST-mode protocol (first physical test; D-051 point 4)

- Scope: Maps Burger organization / branch; a real paired POS device with a real PIN session and
  membership; the lab screen enabled on that one device only.
- Attempt: order-less (amount-only, small amount, `order_id` NULL); mode `test`; one frozen identity
  minted and persisted before the first provider request; both provider keys derived from it.
- Never: `record_payment`, a `payments` row, a receipt number, a shift or drawer effect, an order-history
  or kitchen change, a Dashboard revenue change, a tenant Activity-log entry (**D-053** point 4).
- Transport: UNKNOWN on timeout or dropped connection; no automatic retry; recovery by the status
  lookup under the same identity; an exact-repeat refusal is "already submitted".
- Fail closed: no pad prompt, a credential or environment rejection, or an out-of-contract reply ends
  the attempt UNKNOWN or refused; the run stops; the sanitized mismatch (field names, codes, timings;
  never values) is reported for targeted escalation.
- Evidence: the sealed test report lists attempt identities, states, return codes and timings only.
- Retention: TEST rows carry `retention_until = created_at + 90 days`; an incident hold keeps a row; the
  operator-only audited purge deletes only expired, unheld TEST rows; LIVE rows are never deleted by any role or RPC (long-term retention per **D-013** / **Q-005**; **D-053** point 4).

## 6. Money and data rules (D-052 points 4 and 6)

- Integer minor units everywhere; the adapter's two-decimal text formatting is the only decimal
  boundary; strict minor-unit equality on lookups; currency must match the order currency (ILS for the
  pilot tenant); the tip object is omitted and a non-zero tip amount fails closed.
- Persist only: provider reference, approval number, voucher number, last four digits, brand code,
  approval type, return code and message, entry mode, payment method, status code, deposit id,
  provider timestamp, minor amounts with currency.
- Never persist, log, print or display: full or masked card number, BIN, expiry, token, raw or
  encrypted processor records, receipt texts, request bodies, any field outside the allowlist.

## 7. Scope allowlist and forbidden paths

- Allowed by ticket: 001A/001B docs; 001C `packages/data_remote`, `packages/auth_identity`,
  `packages/l10n` ARBs; 001D one forward-only migration (including the single re-creation of `app.sync_push` that adds the claim-guard call to its five existing arms) + pgTAP plus the Dashboard `kAuditActionRegistry` entries, `_displayableKeys` labels and ar / he / en audit titles under the ORDER-EDIT-001A owner-approved exception pattern (API §4.33); 001E one new function directory, an
  additive `config.toml` block and one explicit CI test step; 001F `apps/pos` payment files listed in
  the preflight; 001G tests only.
- Forbidden: `storefront/**`, `supabase/functions/web-order-submit/**`,
  `supabase/functions/pos-web-order-decision/**` (precedent only), `supabase/functions/storefront-media-publish/**`,
  `supabase/functions/_shared/**`, Storefront / web-order migrations and docs, the `bizbot-storefront`
  Vercel project, any unregistered Codex location; `apps/pos/lib/src/widgets/order_action_row.dart`
  (PR #314), `packages/printing/**` and the receipt preview (PR #315) in phase 1;
  `tools/android_release/**`, `docs/ANDROID_RELEASE_SIGNING.md`, `tools/vercel/ignore-build.mjs`,
  lockfiles and generated files; the body of `app.record_payment`; the D-018 enumerations; the
  dirty `BIZBOT-INSTANT-NOTIFICATION-WAKE-001` worktree.
- Base and order: every ticket branches from a fresh `origin/main`; #314 and #315 do not block
  001A–001E; merge or close them before 001F.

## 8. Validation and rollout gates

| Gate | Proof |
|---|---|
| Unit / integration (fakes) | float-free money; derived keys deterministic; journal sibling-key round trip and older-build quarantine; gate fail-closed; approved / declined / UNKNOWN / released paths; Resume never re-charges; two tills refused before any provider call; restart mid-attempt recovers; the legacy `card` tender hidden on a LIVE terminal-enabled till; typed `payment_in_progress` / `card_terminal_required` refusals; ar / he / en. |
| Shared transport | both boot compositions forward the capability; blocked session refuses; late response after timeout causes no second transmission; dedicated timeout independent of the 15 s default. |
| Edge adapter | exact environment-read allow-list and `config.toml` pin; JWT forwarding; closed-set projection; timeout → UNKNOWN; no body logging; static guard against float parsing on money. |
| T-023 (pgTAP + the Edge test lane + static guard) | role denies, forced RLS, immutability, proof-derived tenant context, the enumerated `authenticated` grants (context proof, `free_order`, owner read) and every service-only pair refused to `authenticated`, the `app.sync_push` guard (competing operations refused on a claimed order, the matching approved identity recorded once, hand-recorded `card` refused on a LIVE terminal-enabled till, other devices unchanged, `app.record_payment` hash unchanged), `free_order` confirmation-bound and never for an approved attempt, exact-device mapping and one `credential_ref` per restaurant, TEST mode never writes `payments` / receipt / shift / order history / Activity log and is purged only after retention, one in-progress attempt per order, kitchen exclusion, accountant read-only, support mode denied; the adapter makes no service-only call before a successful proof. |
| Deploy (001H) | migration PRE/POST per OPERATIONS §4.2 and DEPLOYMENT §18.2 (patterned on §17.2); function deployed with every flag OFF; secret NAMES verified, values never read back. |
| Physical test (001H) | TEST mode per §5 only, owner present; hosted PRE/POST queries prove no Maps Burger production row changed. |
| Rollback | master flag OFF → operator revision OFF → per-device toggles OFF (status reads and recording keep working so in-flight attempts resolve); keep every ledger row; no replay; forward-only migrations. |

## 9. Owner decisions still open and targeted escalation list

Owner decisions recorded on 2026-10-21 as **DECISION D-053**: Q-051 (orphan approval / same-day void),
Q-053 (plan tier), Q-054 (per-restaurant credentials, merchant of record), Q-055 (TEST-mode traces and
retention), Q-056 (one Android till) and Q-057 (hand-recorded card). Still open: **Q-052** (receipt / tax
document law — the accountant's confirmation is mandatory before the first LIVE charge and blocks nothing in
001D–001F) and **Q-047..Q-050** (test-driven discovery; none blocks 001D–001F).

Targeted escalation to vendor support, only if discovery fails or a mismatch appears (never a
blocker): test environment host and credentials mapping and the purpose of the extra key (**Q-047**);
status-lookup semantics for never-received / declined / pending attempts (**Q-048**); key length and
character rules and the duplicate-check window (**Q-049**); device model, identifier, binding and the
masking setting (**Q-050**); maximum pad blocking time, return codes for pad timeout / offline / busy /
after release, behaviour when the HTTP connection drops mid-call; release-versus-tap race; deposit
timing; tip amount unit; customer-present expectation.
