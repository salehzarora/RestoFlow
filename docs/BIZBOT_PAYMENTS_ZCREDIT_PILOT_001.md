# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001 — card-present POS payments pilot (Z-Credit PIN pad)

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001` (umbrella; tickets 001A–001H below — 001G-DASHBOARD-VERIFICATION and 001H-PILOT-OPS approved by the owner on 2026-10-21 — plus the independent follow-ups `BIZBOT-PAYMENTS-ZCREDIT-HYGIENE-001` and `DASHBOARD-COLLECTED-LABEL-001`).
Decisions: **DECISION D-051** (scope, architecture, gates) and **D-052** (lifecycle, identity, money, data).
Open questions: **Q-047..Q-056**. Base of this packet: `origin/main` `e9aec540` (merge of PR #359, 2026-10-21).
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
  (Free) / 400 s (paid), 2 s CPU. A background continuation runs only within the wall clock.
- The Dashboard classifies `method='card'` correctly on the intended tender surfaces and every total
  reads `status='completed'` only. The all-tender "Cash collected" label and the sales-summary fallback
  are separate defects of `DASHBOARD-COLLECTED-LABEL-001`, whose deployment — or the owner's recorded
  acceptance of the mislabel — gates LIVE enablement; the pilot's only Dashboard change is the exact
  [MVP_SCOPE](MVP_SCOPE.md) §5 exception (amended 2026-10-23, round 6).
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
| Private provider-attempt ledger (`app` schema) | 001D | tenant columns (`organization_id`, `restaurant_id`, `branch_id`, `device_id`), optional `order_id` (NULL in TEST mode), `local_operation_id`, mode `test` / `live`, state (`sent` / `approved` / `declined` / `unknown` / `released`; `recorded` and `approved_unrecorded` are derived; `released` is provisional until a status lookup), both full internal key digests and both provider keys as sent (D-052 point 2), `amount_minor` + `currency_code`, allowlisted, field-validated provider codes only (no provider free text), timestamps; UNIQUE (`organization_id`, `device_id`, `local_operation_id`); partial UNIQUE on `order_id` while in progress; forced RLS, deny policies, no app-role grants; append-only evidence rows; plus the tenant-scoped PIN-pad mapping table (opaque `terminal_ref` per branch / device; no credential or identifier; populated only at TEST secret setup). |
| Ledger RPCs | 001D | SECURITY DEFINER writer / claim / finish / status on the real PIN + device + employee proof (pattern `app.pos_web_order_context`); operator revision setter pinned to the pilot organization / branch, default OFF, bounded window; typed RETURN envelopes. |
| Edge provider adapter (proposed `pos-card-charge`) | 001E | caller JWT forwarded; exact key set; `start` (claim → provider commit under a bounded deadline → ledger outcome; expiry = UNKNOWN), `status` (ledger first, then the provider lookup by the merchant key), `release` (advisory); reads only documented NAMES through an injected, shape-validated accessor pinned by a static guard; never logs bodies; float-free money module. |
| Runtime configuration | 001H (values) / 001D (table) | master flag (exact `true`) and one provider configuration secret (JSON: environment, base URL, terminal credentials and PIN-pad identifiers keyed by opaque terminal references), installed only at TEST secret setup; the tenant-scoped mapping table that holds only opaque references per branch / device ships with the 001D migration. |
| Shared transport capability | 001C | new capability interface in `packages/data_remote` with its own timeout, implemented by the Supabase, upgradable and guarded transports (`packages/auth_identity`). |
| POS Payment Lab | 001F | decorator on `PaymentAttemptSender`; provider-leg sibling journal key; polling; outcomes `providerDeclined`, charged-unrecorded, provider status unavailable; per-device default-OFF lab screen; `method='card'` unchanged; `order_action_row.dart` untouched. |
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
  or kitchen change, a Dashboard revenue change, a tenant Activity-log entry (**Q-055**).
- Transport: UNKNOWN on timeout or dropped connection; no automatic retry; recovery by the status
  lookup under the same identity; an exact-repeat refusal is "already submitted".
- Fail closed: no pad prompt, a credential or environment rejection, or an out-of-contract reply ends
  the attempt UNKNOWN or refused; the run stops; the sanitized mismatch (field names, codes, timings;
  never values) is reported for targeted escalation.
- Evidence: the sealed test report lists attempt identities, states, return codes and timings only.

## 6. Money and data rules (D-052 points 4 and 6)

- Integer minor units everywhere; the adapter's two-decimal text formatting is the only decimal
  boundary; strict minor-unit equality on lookups; currency must match the order currency (ILS for the
  pilot tenant); the tip object is omitted and a non-zero tip amount fails closed.
- Persist only closed classes and validated codes: provider reference, approval number, voucher
  number, last four digits, brand code, approval type, the integer return code and a normalized
  return class, entry mode, payment method, status code, deposit id, provider timestamp, minor amounts
  with currency — each after its field-specific character-set / length rule and the no-card-data rule
  (a failing field is dropped). The vendor's free-text message is inspected transiently and dropped;
  no provider free text is ever stored, logged, audited or returned (amended 2026-10-23, round 6).
- Never persist, log, print or display: full or masked card number, BIN, expiry, token, raw or
  encrypted processor records, receipt texts, request bodies, any field outside the allowlist.

## 7. Scope allowlist and forbidden paths

- Allowed by ticket: 001A/001B docs; 001C `packages/data_remote`, `packages/auth_identity`,
  `packages/l10n` ARBs; 001D one forward-only migration + pgTAP, plus the one Dashboard exception of
  [MVP_SCOPE](MVP_SCOPE.md) §5 — exactly `apps/dashboard/lib/src/data/audit_action_registry.dart`,
  `apps/dashboard/lib/src/data/audit_log_presentation.dart`, `packages/l10n/lib/l10n/app_en.arb`,
  `app_ar.arb`, `app_he.arb`, the `packages/l10n/lib/src/generated/app_localizations*.dart` files
  regenerated from those ARBs and the rendering test `apps/dashboard/test/card_attempt_activity_log_test.dart`; 001E one new function directory, an
  additive `config.toml` block and one explicit CI test step; 001F `apps/pos` payment files listed in
  the preflight; 001G tests only.
- Forbidden: `storefront/**`, `supabase/functions/web-order-submit/**`,
  `supabase/functions/pos-web-order-decision/**` (precedent only), `supabase/functions/storefront-media-publish/**`,
  `supabase/functions/_shared/**`, Storefront / web-order migrations and docs, the `bizbot-storefront`
  Vercel project, any unregistered Codex location; `apps/pos/lib/src/widgets/order_action_row.dart`
  (PR #314), `packages/printing/**` and the receipt preview (PR #315) in phase 1;
  `tools/android_release/**`, `docs/ANDROID_RELEASE_SIGNING.md`, `tools/vercel/ignore-build.mjs`,
  lockfiles and generated files (except the l10n localizations regenerated for the Dashboard exception
  above); the body of `app.record_payment`; the D-018 enumerations; the
  dirty `BIZBOT-INSTANT-NOTIFICATION-WAKE-001` worktree.
- Base and order: every ticket branches from a fresh `origin/main`; #314 and #315 do not block
  001A–001E; merge or close them before 001F.

## 8. Validation and rollout gates

| Gate | Proof |
|---|---|
| Unit / integration (fakes) | float-free money; the full-identity key digests deterministic and domain-separated (status vs duplicate), never from `local_operation_id` alone (D-052 point 2); journal sibling-key round trip and older-build quarantine; gate fail-closed; approved / declined / UNKNOWN / released paths; Resume never re-charges; a second till or a duplicate request refused before any provider call; restart mid-attempt recovers; ar / he / en. |
| Shared transport | both boot compositions forward the capability; blocked session refuses; late response after timeout causes no second transmission; dedicated timeout independent of the 15 s default. |
| Edge adapter | exact environment-read allow-list and `config.toml` pin; JWT forwarding; closed-set projection; timeout → UNKNOWN; no body logging; static guard against float parsing on money; outbound keys only from the sealed formatter configuration — without it `provider_unavailable` and zero provider calls (**Q-049**); the vendor's free-text message never stored, logged or returned. |
| T-023 (pgTAP + the Edge test lane + static guard) | role denies, forced RLS, immutability, no provider free-text column, field-validated provider codes, proof-derived tenant context, TEST mode never writes `payments` / receipt / shift / order history / Activity log (**Q-055** default), one in-progress attempt per order, kitchen exclusion, accountant read-only, support mode denied. |
| Deploy (001H) | migration PRE/POST per OPERATIONS §4.2 and the DEPLOYMENT §17.2 PRE / POST recipe; function deployed with every flag OFF; secret NAMES verified, values never read back; no provider secret installed before the sealed **Q-047** and **Q-049** evidence. |
| Physical test (001H) | only after the sealed non-settling TEST facility evidence (§5 gate, **Q-047**); TEST mode per §5 only, owner present, one session kept for the whole run; hosted PRE/POST queries prove no Maps Burger production row changed. |
| Rollback | master flag OFF → operator revision OFF → poller off; keep every ledger row; no replay; forward-only migrations. |

## 9. Owner decisions still open and targeted escalation list

Open owner decisions: **Q-051** (orphan approval / same-day void), **Q-052** (receipt law),
**Q-053** (plan tier), **Q-054** (per-tenant credentials, merchant of record), **Q-055** (TEST-mode
traces). None blocks 001B–001F beyond the ASSUMPTION defaults recorded in **D-052** (Q-055 → the 001D
audit rule); each is revisited before production enablement. **Q-056** is resolved by D-051 point 9
(Android POS only, 2026-10-23). Hard owner gates on every real provider action: **Q-047** (the sealed
non-settling TEST facility evidence) and **Q-049** (the sealed key-format evidence); neither blocks
code or fake-provider work.

Vendor support is the route to the two gating evidence packages — the exact non-settling TEST
facility (test environment host, credential record and mode, terminal / PIN-pad binding, test-card
status, no-settlement evidence and the purpose of the extra key — **Q-047**) and the key length and
character rules (**Q-049**); without them nothing real runs. Targeted escalation, only if discovery
inside the sealed facility fails or a mismatch appears: status-lookup semantics for never-received /
declined / pending attempts (**Q-048**); the duplicate-check window (**Q-049**); device model,
identifier and the masking setting (**Q-050**); maximum pad blocking time, return codes for pad timeout / offline / busy /
after release, behaviour when the HTTP connection drops mid-call; release-versus-tap race; deposit
timing; tip amount unit; customer-present expectation.
