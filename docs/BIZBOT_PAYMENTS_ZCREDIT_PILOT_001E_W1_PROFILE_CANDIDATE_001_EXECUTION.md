# BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-PROFILE-CANDIDATE-001 — execution packet: the unwired Z-Credit WebService PIN PAD source profile candidate

Work ID: `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-PROFILE-CANDIDATE-001` (a ticket of the umbrella
[BIZBOT-PAYMENTS-ZCREDIT-PILOT-001](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001.md)).
Controlling contract: [API_CONTRACT](API_CONTRACT.md) §4.55 with **D-052** .. **D-064**. The adapter is described by
[the 001E execution packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md) (§6 engine and the W1 review checklist),
its lookup precedence by [the W1-LOOKUP-SAFETY-001 packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_W1_LOOKUP_SAFETY_001_EXECUTION.md)
(**D-063**; §8 carries the two missing tests this ticket adds) and its inbound money by
[the INBOUND-MONEY-NORMALIZATION-001 packet](BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_INBOUND_MONEY_NORMALIZATION_001_EXECUTION.md)
(**D-064**). This packet records no **DECISION**, adds no **OPEN QUESTION** and allocates no ID.

## 1. Authorization and boundary

- Command-room authorization of 2026-10-29, "UNWIRED SOURCE PROFILE CANDIDATE": foundation accepted on the D-064
  packet-closeout head `ca8edb03223a7ac453d5b3a934296023a1e6bc3f` (parent `f7d5be5d80bfd1e454a44420a70bc4317e4f5b82`);
  the D-064 executable source stays accepted and no executable correction round is requested. The instruction is kept
  outside Git with a SHA-256 sidecar (`2c0847785938bd565f1a562f1b85cd0a28b779526667b2011c8ca65478949a52`).
- The command room confirms the provider-money rule: a missing key, JSON null, an empty string or a string of
  Space_Separator characters only is ABSENT and never zero; every non-empty JSON string (other than such a blank one) is
  refused for a provider-money field; a JSON number zero canonicalizes to `0.00`; inbound provider JSON numbers accept
  zero to two decimal places and canonicalize to `X.XX`; outbound provider money stays the canonical `X.XX`.
- Scope: one function-local source module holding an UNWIRED, reviewed profile candidate for the documented Z-Credit
  WebService PIN PAD wire contract, its tests, two bounded documentation clarifications (§4) and this packet. It is not
  authorization to connect Z-Credit, use credentials, call an endpoint, operate a terminal or close **Q-047** /
  **Q-049**. `index.ts` keeps `providerProfile: null` throughout; no runtime flag, configuration or secret schema refers
  to the candidate.
- Evidence: only the accepted, sanitized W1 wire-evidence package (§3). Vendor originals, raw e-mails, credential and
  test-card files are not opened; the rows that cite the vendor's PIN PAD guide (S4) are used through the matrix's own
  sanitized extracts.
- Process: no push, PR, merge, hosted change, deployment, secret access, provider request, vendor inquiry, terminal or
  card use, printer or APK action; no amend, rebase, reset, deletion or history rewrite; no Codex review; one focused
  fresh-context Claude review of the delta (§11); no background monitor.
- Branch `feat/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-PROFILE-CANDIDATE-001-unwired-source-profile`, created at
  `ca8edb03` in its own worktree, stacked on the unmerged D-064 (`ca8edb03`), W1 (`140be040`), G1 (`295cacb6`), 001E
  (`d5456624`) and #370 (`54b19ab5`) heads; local only. `main` is recorded separately (§2) and is not merged into this
  stack.

## 2. Source anchor (preflight 2026-10-29T00:38:52Z, read-only)

| Item | Value |
|---|---|
| Base | `ca8edb03…` (tree `acf010a541912495f29a6744cfd3a53d5383d267`, parent `f7d5be5d…`); the new branch points at it with no commit on top before this packet; clean worktree, no upstream |
| D-064 | the D-064 branch and worktree at `ca8edb03`, clean |
| D-063 (W1) | `140be040fafb3f21f6af3cacfa8b8d81db251246` (tree `cbfda1f5bfa31667d102593d1bfedd595fb35cea`), clean |
| G1, 001E | `295cacb6c50226da9cba99e769fac0680ee14fcc`, `d545662476cea8cfae41729b15034dc713e10a19`; both clean |
| #370 / #371 | OPEN drafts at `54b19ab58ce72a2fa9a43860e31181a08222b254` / `53d6a6adc38f308b7ed6b0dd62177e6edd5ad5ce` |
| main | the main checkout at `556136f1` with no tracked change; actual `origin/main` = `435ada86fe10c00c94c0fdfdb0395559587489eb` (`git ls-remote`; PR #373, another ticket, merged 2026-10-28T23:32:54Z); merge base with this stack `d2079820`; the 7 main commits since it change 44 files, none in this ticket's file set (§4); 8 of those files are other tickets' migrations (7) and a SQL test, untouched here |
| Ownership | no local or remote-tracking ref holds a commit on `supabase/functions/pos-card-charge/` outside the base's history; no worktree has an uncommitted change there; no remote ref or PR names this Work ID |
| IDs | the highest `## DECISION` header is D-064 at the base (D-058 on `origin/main`, D-060 on #370, D-061 on #371) and no ref carries D-065; the highest allocated question row is Q-057 (next free Q-058); this ticket allocates none |
| Node suite at the base | 158 / 158 on Node 22.14.0 and on Node 24.19.0 |

## 3. Pinned evidence and heads

**The accepted W1 wire-evidence package** (BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-EVIDENCE-001, accepted by the command
room on 2026-10-28), kept outside Git:

| Artifact | SHA-256 |
|---|---|
| `BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-EVIDENCE-001-sanitized-review-package.zip` | `634d379478a0cd3f90a974f1ec96960031fab4d7fe07b90cc8dcec4744e5f004` |
| its `package/SHA256SUMS.txt` (21 members, all verified at preflight) | `47c045af980359484a9b7d6490123e156668d824c3e24f014d39ffe688f291b4` |
| `EVIDENCE_MATRIX.md` (94 rows: FACT 75, INFERENCE 8, UNKNOWN 11) | `60c701130187cecb93479c2cf16f3f2518eed663465b847f72ef0bdb76208c6d` |
| `GAPS_AND_GATES.md` | `4bd7c424703101fde511389e3df64cf49bde4b976df39ea5f326f4e62d781b22` |
| `SOURCE_REGISTER.md` | `7446ee1a2ebba5009305de0a3935b0917554855d3045666281862fe39a13f0d2` |
| `REDACTED_REQUEST_FIXTURES.json` (INFERENCE; a test oracle only) | `cd1288a64010d7322db59af76254b7cb731a517bc6d4ef04c720c53450ab2cc2` |
| `REDACTED_REPLY_FIXTURES.json` (documented examples FACT, constructed ones INFERENCE; a test oracle only) | `bd09487815ba197822f224b3d27d5ee80b24adb3a6c3dab3b1019537c02a2098` |

**The sources the candidate's FACT rows cite** (SOURCE_REGISTER; SHA-256 of the raw bytes):

| ID | Source title | SHA-256 |
|---|---|---|
| S1 | Z-Credit Gateway API (WS), OpenAPI 3.1.0 specification (public) | `ad6e70d61e4cba8ee086127f237e394732ad9d62528cd96325b10fd189588a25` |
| S2 | Z-Credit Gateway API (WS), "Integration Guide" page (public) | `6ed0c0e860a9c087e52b5591dc80f762dde297cbfe055a26f3e38358e632d6b9` |
| S4 | "Working with PIN PAD" technical guide (vendor .docx, non-credential; Hebrew) | `01a5288811727626144fb315ea289310af76c08dd9c2d011cbd447c2cbb65a5e` |

**Accepted heads:**
- **D-063** — `140be040` (W1-LOOKUP-SAFETY-001; review package
  `1e72661f5081a879da29c1329b9a8df2521fa4cac5a440461912052799c558b5`);
- **D-064** — source `741e55d3677f48c5dbd534308814ca5748883cf8` (tree `3153412a26d945d0767c6a531daedf836bbeab45`;
  review package `b9464ca8222960c25bb1d9a4d78b60936807402c185788f2f7a849b193b6b44c`), documentation consistency
  `f7d5be5d80bfd1e454a44420a70bc4317e4f5b82`, packet closeout `ca8edb03223a7ac453d5b3a934296023a1e6bc3f` (this
  ticket's base).

## 4. Exact files

| File | Change |
|---|---|
| this packet | new |
| `docs/TESTING_STRATEGY.md` | the 001E line's **D-064** vectors only: the absent rule made explicit (absent, not refused, and never zero), the string clause narrowed to every other non-empty string, and the numeric-zero vector (`0`, `0.0`, `0.00` → `0.00`) |
| `docs/BIZBOT_PAYMENTS_ZCREDIT_PILOT_001E_EXECUTION.md` | the dated **D-064** note of §8 only: the same distinction |
| `supabase/functions/pos-card-charge/lib/provider/zcredit_profile.mjs` | new: the candidate, plain data in the engine's closed profile schema; it imports nothing |
| `supabase/functions/pos-card-charge/test/zcredit_profile.test.mjs` | new: the tests of §9 |
| `supabase/functions/pos-card-charge/test/fixtures.mjs` | the scripted world also routes a provider request by its profile's own routes (the synthetic `/synthetic/<op>` routing unchanged) |
| `supabase/functions/pos-card-charge/test/static_guard.test.mjs` | the reviewed file set names the candidate module |

Not changed: `index.ts` (`providerProfile: null`), `handler.mjs`, `lib/provider/engine.mjs`, `lib/money.mjs`,
`lib/json.mjs`, `lib/config.mjs` and every other function source, the function's `CONTRACT.md`, API_CONTRACT,
DECISIONS (**D-064** included), MONEY_AND_TAX_SPEC, OPEN_QUESTIONS, DEPLOYMENT, every migration and SQL test,
`config.toml`, CI, the 001D key formatter, #370, #371, the earlier branches, packages and evidence folders, and every
vendor evidence artifact. The accepted packet closeout (`ca8edb03`) is not edited.

## 5. FACT / INFERENCE / UNKNOWN handling

- **FACT only.** Every route, member name, accepted JSON type, constant and code in the module traces to a FACT row of
  the matrix (§6). The two BIZBOT-internal names — the profile `version` and the credential record's member names
  `terminal_number` and `password` — are not vendor facts and carry no value.
- **INFERENCE rows are never the source of a module value:**

  | Row | Subject | Handling |
  |---|---|---|
  | E1-12 | the case of the `PINPAD` prefix | the upper-case bytes are E1-11's FACT extract ("the PINPAD prefix"); whether the gateway is case-insensitive stays E2-B |
  | E1-15 | CVV | an omission: the module has no CVV member |
  | E1-35 | the redacted request fixtures | a test oracle outside Git (§9), never a module value |
  | E2-02 | error delivery and its HTTP status | an engine property (any non-2xx or non-JSON reply fails closed); E2-B |
  | E2-12 | the gateway's approval-type byte form | no form is added from its inference (which byte form the gateway sends stays E2-B, §7.3); `"03"` is listed because E2-10 (FACT) names it as the form of the documented examples — E2-12's extract only locates those examples (S1 raw lines 614 and 754) — and `"01"`, `"02"`, `"04"`, `"05"`, `"06"`, `"08"` are listed nowhere |
  | E2-33 | the redacted reply fixtures | a test oracle outside Git (§9) |
  | E3-08 | keys absent from the lookup reply | nothing to map; a found lookup cannot be cross-checked against its key |
  | E5-04 | no amount or currency on the commit reply | nothing to map; the one reply map serves all three operations |

- **UNKNOWN rows are never filled by a guess:**

  | Row | Subject | Handling |
  |---|---|---|
  | E1-03 | the TEST base URL and the test credentials | no URL or value in the module: **Q-047** (§7.2) |
  | E1-10 | the separate test-data KEY | no member: **Q-047** (§7.2) |
  | E2-23, E2-24 | not-found and pending statuses and return codes | `status_not_found`, `status_pending`, `lookup_not_found` and `lookup_pending` are empty: **Q-048** / E2-B |
  | E2-31 | whether a PinPad commit reply carries `TipAmount` | **D-064** makes both answers safe (absent = no tip; `0` = `0.00`); E2-B confirms |
  | E3-03 .. E3-06 | the keys' encoding, length, character set, duplicate scope and window | no formatter: **Q-049** (§7.1) |
  | E5-03 | the fraction-digit form of an echoed amount | **D-064** reads zero to two decimals; E2-B confirms |
  | E5-05 | documented amount limits | none: the 001D TEST / LIVE caps stay RestoFlow's own |

- **D-063 stays mandatory.** The candidate lists only the documented statuses, so every other present status — an
  unlisted or unreadable one — is the `out_of_contract` anomaly before any fallback.
- **E4 optional fields stay UNMAPPED** (none is needed for phase 1; GAPS §3):

  | Engine key | Vendor member | Row |
  |---|---|---|
  | `provider_reference` | `ReferenceNumber` | E4-01 |
  | `approval_number` | `ApprovalNumber` | E4-02 |
  | `voucher_number` | `VoucherNumber` | E4-03 |
  | `deposit_id` | `DepositID` | E4-04 |
  | `card_last4` | `Card4Digits` (and the lookup's `CardNumber`) | E4-05 |
  | `card_brand_code` | `CardBrandCode` | E4-06 |
  | `pan_entry_mode` | `PanEntryMode` | E4-07 |
  | `payment_method_code` | `PaymentMethod` | E4-08 |
  | `provider_saved_at` | `SaveDate` (no UTC offset) | E4-09 |

  Never mapped (E2-32, E4-10, E4-11): `CardNumber`, `CardBIN`, `ExpDate_MMYY`, `Token`, `HolderID`, the receipt texts,
  `ResultRecord`, `IntOt`, `IntOt_JSON`, `CardName`, `CardIssuerCode`, `CardFinancerCode`, customer data, `ExtraInfo`,
  `ItemDescription`, `DealTypeCode`, `CreditTypeCode`, `J`, the installment members, the tip echo, the invoice response,
  `ReturnMessage` (E2-05: no provider free text) and the lookup's phone flag `IsTelAuthAbilty` (E2-16, §7.3).

## 6. The candidate and its evidence (evidence-item-to-code matrix)

Each row names the module element, its value, the matrix row (all FACT), the source (§3) and the page or section as
the matrix records it. "Raw line" is the vendor document's own line number in S1.

**Routes**

| Element | Value | Row | Source | Page / section |
|---|---|---|---|---|
| `routes.commit` | `/Transaction/CommitFullTransaction` | E1-04 | S1 | paths./Transaction/CommitFullTransaction (raw lines 538, 542) |
| `routes.lookup` | `/Transaction/GetTransactionStatusByTransactionUniqueIdForQuery` | E1-05 | S1 | paths./Transaction/GetTransactionStatusByTransactionUniqueIdForQuery (raw lines 821, 827) |
| `routes.release` | `/Transaction/ReleasePinpad` | E1-07 | S1 | paths./Transaction/ReleasePinpad (raw lines 941, 947) |

**Commit request** (members in this order)

| Member | Source of the value | Row | Source | Page / section |
|---|---|---|---|---|
| `TerminalNumber` | credential (record member `terminal_number`) | E1-08 | S1, S2 | info.description > Authentication (raw line 28); CommitFullTransactionRequest/properties/TerminalNumber (raw line 1370); Integration Guide > Authentication |
| `Password` | credential (record member `password`) | E1-09 | S1 | CommitFullTransactionRequest/properties/Password (raw lines 1373-1375) |
| `Track2` | the PIN pad, prefix `PINPAD` (no separate `PINPAD_ID` member: E1-13) | E1-11, E1-13 | S1, S4, S2 | info.description > PinPad Activation; CommitFullTransactionRequest/properties/Track2 (raw lines 43, 1379); S4 paragraphs 4-5; Integration Guide > Authentication |
| `CardNumber` | constant `""` | E1-14 | S4 | paragraph 8 |
| `ExpDate_MMYY` | constant `""` | E1-14 | S4 | paragraph 8 |
| `TransactionSum` | the amount: the canonical `X.XX` number token from integer minor units | E1-16, E5-06 | S1 | CommitFullTransactionRequest (required; properties/TransactionSum) (raw lines 1366, 1395); DepositTerminalResponse (raw line 2154) |
| `TransactionType` | constant `"01"` | E1-18 | S1 | CommitFullTransactionRequest/properties/TransactionType (raw line 1418) |
| `CurrencyType` | the currency (`currency_request`: ILS → integer `1`) | E1-17, E5-01 | S1 | CommitFullTransactionRequest/properties/CurrencyType (raw lines 1422, 1425) |
| `CreditType` | constant integer `1` | E1-19 | S1 | CommitFullTransactionRequest/properties/CreditType (raw lines 1430, 1433) |
| `NumberOfPayments` | constant integer `1` (as in the documented request example) | E1-20 | S1 | CommitFullTransactionRequest/properties/NumberOfPayments (raw lines 1399, 1400); the request example (raw line 566) |
| `J` | constant integer `0` (no J2: E1-33) | E1-22, E1-33 | S1, S4 | CommitFullTransactionRequest/properties/J (raw lines 1440, 1443); S4 paragraph 11 |
| `IsCustomerPresent` | constant `true` | E1-23 | S1 | CommitFullTransactionRequest/properties/IsCustomerPresent (raw line 1450) |
| `AuthNum` | constant `""` | E1-28 | S1 | CommitFullTransactionRequest/properties/AuthNum (raw line 1456); Phone Authorization > Resending with the code (raw line 98); the request example (raw line 574) |
| `TransactionUniqueIdForQuery` | the stored status-recovery key, unchanged | E1-24, E3-01 | S1 | CommitFullTransactionRequest/properties/TransactionUniqueIdForQuery (raw line 1490) |
| `TransactionUniqueID` | the stored duplicate-check key, unchanged | E1-25, E3-02 | S1 | CommitFullTransactionRequest/properties/TransactionUniqueID (raw line 1494); Duplicate Transaction Check (raw lines 170, 175) |
| `UseAdvancedDuplicatesCheck` | constant `false` | E1-26 | S1 | CommitFullTransactionRequest/properties/UseAdvancedDuplicatesCheck (raw lines 1502, 1504, 1508) |

Omitted on purpose: the `Tip` object (E1-27, S1 Tips (PinPad only), raw line 164), `FirstPaymentSum` and
`OtherPaymentsSum` (E1-21, raw line 1406), the personal, free-text, J5-capture, wallet, display and invoice members
(E1-29, raw line 1366), CVV (E1-15) and any KEY member (E1-10).

**Lookup request**

| Member | Source of the value | Row | Source | Page / section |
|---|---|---|---|---|
| `TerminalNumber`, `Password` | credential (`terminal_number`, `password`) | E1-30 | S1 | QueryByUniqueIdRequest (raw lines 1953, 1965) |
| `UniqueQuery` | the stored status-recovery key, unchanged | E1-30, E3-01 | S1 | QueryByUniqueIdRequest (raw line 1965) |

**Release request**

| Member | Source of the value | Row | Source | Page / section |
|---|---|---|---|---|
| `TerminalNumber`, `Password`, `Track2` | credential, credential, the PIN pad with the prefix `PINPAD`; no key (E1-32) | E1-31, E1-32 | S1 | ReleasePinpadRequest (raw lines 2006, 2018); paths./Transaction/ReleasePinpad (raw lines 947, 948) |

**Reply map** (one map for the three operations; each key accepts only its documented JSON type)

| Engine key | Vendor member, accepted type | Row | Source | Page / section |
|---|---|---|---|---|
| `error_flag` | `HasError`, boolean | E2-03 | S1 | BaseResponse/properties/HasError (raw line 1282) |
| `provider_return_code` | `ReturnCode`, number | E2-04 | S1, S2 | BaseResponse/properties/ReturnCode (raw line 1285); info.description > Gateway Error Codes (raw line 242); Integration Guide > Shva Error Codes |
| `approval_type` | `ApprovalType`, string | E2-09 | S1 | TransactionResponse/properties/ApprovalType (raw line 1621) |
| `phone_authorization` | `IsTelApprovalNeeded`, boolean | E2-15 | S1 | TransactionResponse/properties/IsTelApprovalNeeded (raw line 1575); Phone Authorization > Reading the response (raw line 82) |
| `provider_status_code` | `StatusCode`, number | E2-17 | S1 | TransactionStatusResponse/properties/StatusCode (raw line 1784) |
| `provider_amount` | `TransactionSum`, number | E2-26 | S1 | TransactionStatusResponse/properties/TransactionSum (raw line 1712); the lookup 201 example (raw line 865) |
| `provider_currency` | `CurrencyTypeCode`, number | E2-27, E5-02 | S1 | TransactionStatusResponse/properties/CurrencyTypeCode (raw lines 1765, 1766); the lookup 201 example (raw line 877) |
| `tip_amount` | `TipAmount`, number | E2-30 | S1 | TransactionResponse/properties/TipAmount; info.description > Tips (PinPad only) (raw lines 1633, 161) |

**Codes**

| List | Values | Row | Source | Page / section |
|---|---|---|---|---|
| `return_success` | `"0"` | E2-04, E2-06 | S1, S2 | BaseResponse/properties/ReturnCode (raw line 1285); Integration Guide > Quickstart |
| `return_duplicate` | `"-88001"`, `"-88002"` | E2-07, E2-08 | S1 | info.description > Gateway Error Codes (raw lines 240, 241) |
| `approval_approved` | `"1"`, `"3"`, `"03"`, `"5"`, `"8"` | E2-10 | S1 | TransactionResponse/properties/ApprovalType (raw lines 1623, 1625, 1627, 1630); E2-10 names `"03"` as the form of the documented examples, but its own location column lists only these description lines: the commit 201 example (raw line 614) is recorded by E2-12 (INFERENCE, on the byte form) and E2-31 (UNKNOWN), the CompleteJ5Transaction 201 example (raw line 754) by E2-12 alone, and the documented example RX-01 reproduces the value |
| `approval_declined` | `"2"`, `"4"`, `"6"` | E2-11 | S1 | TransactionResponse/properties/ApprovalType (raw lines 1624, 1626, 1628) |
| `status_approved` | `"1"`, `"2"` | E2-18 | S1 | TransactionStatusResponse/properties/StatusCode (raw lines 1785, 1786) |
| `status_voided` | `"3"` | E2-19 | S1 | StatusCode (raw line 1787) |
| `status_refunded` | `"4"` | E2-20 | S1 | StatusCode (raw line 1788) |
| `status_partial_refund` | `"6"` | E2-21 | S1 | StatusCode (raw line 1789) |
| `status_preauthorization` | `"900"`, `"901"`, `"902"`, `"903"`, `"904"` | E2-22 | S1 | StatusCode (raw lines 1790, 1794) |
| `status_not_found`, `status_pending`, `lookup_not_found`, `lookup_pending` | empty | E2-23, E2-24 (UNKNOWN) | — | deliberately empty (§5) |
| `currency_request` | ILS → integer `1` | E1-17, E5-01 | S1 | CommitFullTransactionRequest/properties/CurrencyType (raw lines 1422, 1425) |
| `currency_reply` | `"1"` → ILS (`2` USD and `3` EUR stay unmapped: E5-07) | E2-27, E5-02 | S1 | TransactionStatusResponse/properties/CurrencyTypeCode (raw lines 1765, 1766) |

Left in neither approval list: `"0"` and `"7"` (E2-13), so they stay UNKNOWN. Positive return codes are never a
decline list (E2-14): a reply that carries only one stays UNKNOWN.

## 7. Gates before the candidate can be wired

### 7.1 Q-049 and the key format

- The candidate maps only the documented member NAMES of the two merchant-supplied keys: `TransactionUniqueIdForQuery`
  (commit) and `UniqueQuery` (lookup) for the status-recovery key, `TransactionUniqueID` (commit) for the
  duplicate-check key. Their values are the keys the 001D claim stored, sent unchanged; the adapter never builds a key.
- It supplies no formatter and does not claim the keys are ready: their encoding, length, character set and the
  duplicate check's scope and window are undocumented (E3-03 .. E3-06, UNKNOWN; `-97` refuses unspecified "special
  characters").
- The wired profile requires: sealed **Q-049** key-format evidence; a matching reviewed 001D formatter version (the
  configuration's `key_format` and the claim's `provider_key_format_version`, one of `alpha16-l20-v1`, `alpha16-l24-v1`,
  `alpha16-l32-v1` today); and the unresolved-attempt retention / deployment gate of §8. No change to SQL or to the 001D
  formatter is authorized here.

### 7.2 Q-047 and the environment

The exact installation gates (GAPS §4); the source candidate alone satisfies none of them:

1. a non-settling TEST environment proof;
2. the exact environment and base URL — the specification declares only the production server, and the TEST base URL
   was never provided (E1-02, E1-03); a base URL stays runtime configuration (`base_url`), never a profile value;
3. the credential mode and scope — a `test` / `development` credential record carrying the members `terminal_number`
   and `password` (values sealed: E1-08, E1-09); if the sealed package shows that the WebService needs the separate KEY
   (E1-10, purpose UNKNOWN), the request specs need one more credential member, as a reviewed profile change;
4. the terminal and PIN-pad binding — the received test data belongs to a logical test terminal; the delivered device's
   PIN-pad identifier is in no allowed source (E1-11; **Q-050**);
5. the test-card status (sealed, never opened);
6. written proof that the facility cannot move or settle real money.

### 7.3 Runtime confirmations (E2-B, Q-048, Q-050)

- E2-B, in the sealed TEST facility after **Q-047** / **Q-049** and the owner action gates of
  [DEPLOYMENT](DEPLOYMENT.md) §18: the acceptance of the exact request bytes (E1-35), including the empty `AuthNum`,
  `CardNumber` and `ExpDate_MMYY` and the device sent only in `Track2` (E1-13, E1-14, E1-28); the `PINPAD` prefix case
  (E1-12); the approval-type byte form (E2-12); `TipAmount` presence and form and the echoed amount form (E2-31, E5-03;
  confirmations only, **D-064** reads both safely); the HTTP status of an error reply (E2-01, E2-02); what the original
  commit returns after a release (E1-32); whether a lookup can report an approved status with `IsTelAuthAbilty` true
  (E2-16: the one reply map reads the commit's `IsTelApprovalNeeded`, so the lookup's phone flag is never read and
  001D M2's lookup phone guard is vacuous for this vendor).
- **Q-048**: the lookup's answer and code for a never-sent, an unknown, a declined and a still-waiting attempt (E2-23,
  E2-24; until then the four not-found / pending lists stay empty), and how a decline arrives (E2-11, E2-14).
- **Q-050**: where `AllowFullCardNumberInResponse` is set (E4-11; `CardNumber` is never mapped) and the delivered
  device's model and binding.
- Documented amount limits: none for the commit `TransactionSum` (E5-05, UNKNOWN); the 001D TEST / LIVE caps stay
  RestoFlow's own until the vendor documents one or E2-B shows one.
- The engine validates a whole profile: the commit and the lookup can only be wired together, and the release cannot be
  wired without them (a profile may leave the release out, with `routes.release` and `request.release` null).

## 8. Deployment and retention gate (the W1-LOOKUP-SAFETY-001 §8.1 carried item)

Once a profile is wired, an attempt that is `sent`, `unknown` or `released` without a resolution is recovered — by
status lookups and releases — through whatever profile is wired at that time; no attempt records a profile version. So:

- **Recovery-compatible change.** A profile change may be deployed while such attempts exist only if it keeps what a
  lookup or release reads identical: the lookup and release routes, the lookup and release request specs (member
  names, value sources, credential record members, prefix), the whole reply map, and every code list or mapping a
  lookup or release reads — all codes except `return_duplicate` and `currency_request`, which only a new commit uses.
  A change of the commit route, of the commit request specs (subject to the next point), of those two lists or of the
  `version` alone is recovery-compatible.
- **Credential record members: configuration first.** The handler requires every credential record member that any of
  the three request specs names — on every credential record before a start (`compatible()`), and on the attempt's own
  record before every lookup and release (`servable()`). A change that adds or renames such a member in any operation
  (the KEY of §7.2 item 3 would be one) is therefore deployed only after every credential record of the configuration
  carries the member; otherwise starts answer `provider_unavailable`, and the lookups and releases of unresolved
  attempts fail closed the same way, until it does.
- **Incompatible change.** Any other change — an incompatible profile replacing the candidate — may be deployed only
  when no attempt is `sent`, `unknown` or `released` without a resolution; until then the old profile stays wired. The
  operator checks belong to [DEPLOYMENT](DEPLOYMENT.md) §18.5 when the profile is wired (not edited here).
- **Static guard (this ticket).** `test/zcredit_profile.test.mjs` pins the SHA-256 of the module's source text, the
  candidate's `version`, two SHA-256 digests of its canonical JSON — the whole data and the recovery projection — and
  the set of credential record members. Any edit of the module (its data, comments or helper) fails the test until the
  pins are updated in the same reviewed change; a changed recovery digest names the incompatible-change gate and a
  changed member set the configuration-order gate. That a data change also takes a new `version` is a review rule the
  test cannot check (no attempt records and no code reads the version). The test also proves which mutations move
  which pin. This is a source / deployment contract, not a database versioning subsystem.

## 9. Test plan (fake transports only; network denied)

New `test/zcredit_profile.test.mjs`, with literal expectations (the engine's own reader is never its oracle):

1. **Schema:** the candidate passes the closed `validateProfile`; its version, routes, request specs, reply map and code
   lists equal literals; the eight essential reply keys are mapped and no other; every pair of code lists is disjoint,
   and success overlaps no duplicate, not-found or pending code; the declined list is exactly `"2"`, `"4"`, `"6"` and
   no padded form (`"01"`, `"02"`, `"04"`, `"05"`, `"06"`, `"08"`) appears in any list; the four not-found / pending
   lists are empty; no E4 field or never-mapped vendor member is mapped; ILS is the only currency; the module is deeply
   frozen.
2. **Request bytes (placeholders only):** the exact commit, lookup and release bodies, URLs and headers through
   `createProvider` and a capturing fake transport — the commit's field names and constants, `Track2` = `PINPAD` + a
   non-sensitive placeholder, `CardNumber` and `ExpDate_MMYY` sent as `""`, no CVV, Tip, `PINPAD_ID` or KEY member, the
   amount as the canonical `X.XX` token (0.01, 1.00, 12.00, 12.30, 12.34, 999 999 999.99), both merchant keys exactly as
   supplied; a currency other than ILS is `NotSendable` before any byte.
3. **Replies (raw bytes, HTTP 201):** the documented approved values approve and the documented declined values
   decline; undocumented approval forms and `"0"` / `"7"` stay UNKNOWN; `-88001` and `-88002` are a duplicate; the phone
   flag and positive return codes never decline; the listed statuses map to approved, voided, refunded, partial refund
   and pre-authorization; any other present status (or a status sent as a string) is `out_of_contract`; an absent status
   (no key, null, blank) stays distinct; a zero tip under **D-064** (`0`, `0.0`, `0.00` → `0.00`; absent → no tip; a
   string → `out_of_contract`; `5` → `amount_mismatch`); whole and one-decimal echoed amounts under **D-064** (`12` →
   `12.00`, `12.3` → `12.30`); the other operations' not-found codes (`-844`, `-9011`, `257`, `443`) never conclude
   not-found or pending; the release outcome; no unmapped member — the documented examples' extras, `IsTelAuthAbilty`
   included — is read or changes an outcome.
4. **Through the handler** (the scripted world routed by the candidate's own routes): a TEST commit approval with
   `TipAmount` `0`, a lookup of a whole-shekel echo and a confirmed release, each with the exact finish arguments.
5. **Carried W1 tests:** a LIVE start in USD (and EUR) answers `provider_unavailable` before any RPC call or provider
   request, under the candidate and the synthetic profile; the deployment / retention guard of §8.
6. **Static:** every string literal of the module is double-quoted and allowlisted, and no comment syntax survives the
   strip, so no value hides in a literal; the whole source, comments included, holds no URL or host, no long or
   separated digit run and no PIN-pad identifier; no import, logging or runtime access; `index.ts` imports only the
   handler and keeps `providerProfile: null`; no function source imports the candidate (tests only); no SQL, migration,
   configuration or CI file names it (that none of them changed is proven by the review package's diff of the branch);
   the existing guards cover the new module (reviewed file set, no hard-coded URL, float-free money, environment
   names).

Also: the full function-local suite on Node 22.14 and 24.19; focused mutations of the module against the new file and
the static guard (`tools/mutate_candidate.py`), once more with the three literal pins skipped; differentials outside
Git — the request bytes against the accepted `REDACTED_REQUEST_FIXTURES.json` (byte-identical after placeholder
substitution) and the classification of every documented and constructed reply of `REDACTED_REPLY_FIXTURES.json`
against its recorded outcome (RC-11 and RC-12 read under **D-064**); a mechanical evidence trace
(`tools/trace_candidate.py`) that checks every module value, names, constants and prefixes included, against its matrix
row's FACT class and own text — evidence tools kept outside Git.

## 10. Results (local; the code and tests are those of `5531256c`; the commit after it changes this packet only)

The logs and tools named here are in the evidence folder outside Git
(`evidence/BIZBOT-PAYMENTS-ZCREDIT-PILOT-001E-W1-PROFILE-CANDIDATE-001-20261029/`).

| Item | Result |
|---|---|
| Commits | `8eee1eb0` this packet before code (sections 1-9); `8cf57ca8` the two documentation clarifications; `4f4d4a2b` the candidate, its tests, the world's route matching and the reviewed file set; `0cc1f591` two behavioural tests after the first mutation run; `5531256c` the review's confirmed findings (tests and this packet's wording); then the results commit (this packet only) |
| Node suite | 187 / 187 on Node 22.14.0 and on Node 24.19.0 at `5531256c` (158 at the base; `zcredit_profile.test.mjs` holds 29 tests); no existing test was removed or weakened; no test reached a real host |
| Evidence trace | `tools/trace_candidate.py` at `5531256c`: 48 module elements, 348 checks — every value equal to its traced value and stated by its row's own text (names, constants and prefixes), 46 FACT rows, every source SHA-256 equal to the register's, E2-23 / E2-24 (UNKNOWN) cited only for the four empty lists, the location of `"03"` as section 6 states; RESULT PASS (`package/EVIDENCE_TO_CODE_MATRIX.md`) |
| Differentials | `tools/differential_candidate.mjs`, 56 checks on each of Node 22.14 and 24.19, all PASS: the commit (12.34 and the whole-amount 12.00), lookup and release bodies are byte-identical to the accepted `REDACTED_REQUEST_FIXTURES.json` fed with the fixtures' own placeholders, with its routes, method, headers and member order; the 3 documented and 12 constructed replies of `REDACTED_REPLY_FIXTURES.json` classify as their recorded outcomes in LIVE and TEST — RC-11 approved with `tip_amount` `0.00` and RC-12 approved with `12.00`, the two cells **D-064** closed |
| Mutations | `tools/mutate_candidate.py`, 63 mutants of the module, every one a valid profile: 63 / 63 killed on Node 22.14 and 24.19. With the three literal pins skipped (the schema literal, the deployment guard, the static literal set): 59 / 63 — the four survivors are pin-only by design (a version-only change, a separated digit run in a comment, a single-quoted literal in dead code, a comment-only edit). The first run, at `4f4d4a2b`, left three behavioural survivors (`ReturnCode` and the phone flag accepted as strings, `42` listed as success), closed by `0cc1f591` |
| Scope | the changed paths are exactly section 4's seven; `index.ts`, `handler.mjs`, `engine.mjs`, `money.mjs`, `json.mjs`, `config.mjs`, `CONTRACT.md`, API_CONTRACT, DECISIONS, MONEY_AND_TAX_SPEC, OPEN_QUESTIONS, DEPLOYMENT, the migrations, the SQL tests, `config.toml` and CI keep the base's blob ids (asserted by the review package's builder, `package/IDENTITIES.txt`); `providerProfile: null`; no function source outside `test/` names the candidate |
| Line endings | every committed blob is LF |

## 11. Fresh-context review and dispositions

One focused fresh-context Claude review ran on `0cc1f591`: a workflow of three read-only lenses (evidence and FACT-only
traceability; behaviour and test strength; scope, documentation and gates) with one refute-first verifier per finding
of MINOR or above, capped at six — 9 agents. An audit of their tool calls found writes only to a scratch folder outside
the repository and the evidence store, and no read of vendor originals, raw e-mails or the W1 package's local captures;
the worktree stayed clean at `0cc1f591`. The review found no behaviour defect and no module value without FACT support.
Of 14 findings (3 claimed MAJOR, 8 MINOR, 3 NOTE), the verifiers refuted both MAJORs they checked (EV-01 to wording,
BT-1 to a NOTE) and confirmed four MINORs; the scope lens's findings were judged first-hand. As instructed, no second
broad round ran: the fixes are tests and wording, proven by the mutation, trace and differential runs of section 10.

| ID | Severity | Finding | Disposition |
|---|---|---|---|
| EV-01 | MAJOR claimed; refuted (wording) | `"03"` was traced to E2-10 with a location E2-10 does not record | `"03"` kept: E2-10 (FACT) names it and the documented examples carry it. Sections 5 and 6 now say exactly where it is located (E2-12, E2-31, RX-01), and the trace checks that location |
| EV-02 | MINOR (confirmed) | The trace did not check the release `Track2` prefix against E1-31 | Fixed in the evidence tool: the prefix is an E1-31 needle, and every prefix must be a needle of its element |
| EV-03 | MINOR (confirmed) | Section 8 called a commit-only credential-member change compatible, although lookups and releases check every member | Fixed in `5531256c`: section 8's configuration-first rule; the guard pins the member set and shows the case |
| BT-1 | MAJOR claimed; refuted (NOTE) | The same, as an incompatible-recovery defect | Recovery reads the same fields once the configuration carries the member, and starts need it as well: handled with EV-03 as a configuration-order rule |
| BT-2, F2 | MINOR (BT-2 confirmed) | The guard did not enforce the version bump it claimed; a comment edit failed nothing | Fixed in `5531256c`: the module's source text is pinned too; a new version is stated as a review rule |
| BT-3, F5 | MINOR (BT-3 confirmed) | The static allowlist saw only double-quoted literals outside comments | Fixed in `5531256c`: no other literal form or comment syntax may survive the strip, separated digit runs are caught, the claim is narrowed; mutants M61-M63 show each channel caught |
| F1, BT-4 | MAJOR claimed (not verified); NOTE | "No SQL / migration / config / CI changes" had no test | Fixed in `5531256c`: a static test that no such file names the candidate; the review package's diff proves none changed (sections 9 and 10) |
| F3 | MINOR | Section 7.3 omitted E5-05 | Added in `5531256c` |
| F4 | MINOR | "No single operation can be wired before the others" was inexact (the release may be null) | Reworded in `5531256c` |
| F6 | NOTE | Section 4 understated the TESTING_STRATEGY edit (the numeric-zero vector) | Reworded in `5531256c` |
| F7 | NOTE | `"03"` has FACT support | No change |

## 12. Readiness per operation, NOT VALIDATED and remaining gates

No operation is runtime-ready, and no gate is closed by this ticket: **Q-047**, **Q-049**, E2-B, **Q-048** and
**Q-050** stay open. Readiness here means that the source candidate is complete from FACT evidence and stays unwired.

**COMMIT_PROFILE_CANDIDATE_READY_UNWIRED**
- FACT rows used: E1-04, E1-08, E1-09, E1-11, E1-13, E1-14, E1-16, E1-17, E1-18, E1-19, E1-20, E1-22, E1-23, E1-24,
  E1-25, E1-26, E1-28, E1-33, E3-01, E3-02, E5-01, E5-06; for the reply E2-03, E2-04, E2-06, E2-07, E2-08, E2-09, E2-10,
  E2-11, E2-15, E2-30.
- Excluded on purpose: E1-10 (KEY, UNKNOWN), E1-12 (prefix case, INFERENCE), E1-15 (CVV, INFERENCE), E1-35 (fixtures,
  INFERENCE), E2-02 (INFERENCE), E2-12 (byte form, INFERENCE), E2-31 (tip presence, UNKNOWN — **D-064** makes both
  answers safe), E3-03 .. E3-06 (key format, UNKNOWN), E5-04 (INFERENCE), E5-05 (UNKNOWN).
- Still required before wiring: the six **Q-047** gates and the three **Q-049** requirements (section 7); E2-B — the
  gateway's acceptance of the exact bytes (the empty `AuthNum`, `CardNumber` and `ExpDate_MMYY`, the device only in
  `Track2`, the `PINPAD` case), the approval-type byte form, `TipAmount`'s presence and form, the HTTP status of an
  error reply; **Q-048** — how a decline arrives; the deployment / retention gate of section 8.

**LOOKUP_PROFILE_CANDIDATE_READY_UNWIRED**
- FACT rows used: E1-05, E1-30, E3-01; for the reply E2-03, E2-04, E2-17, E2-18, E2-19, E2-20, E2-21, E2-22, E2-26,
  E2-27, E5-02, with the shared approval lists (E2-10, E2-11) read only when the status is absent.
- Excluded on purpose: E2-23 and E2-24 (UNKNOWN: the four not-found / pending lists stay empty), E5-03 (UNKNOWN —
  **D-064** reads zero to two decimals), E3-08 (INFERENCE).
- Still required before wiring: **Q-048** — the lookup's answer and code for a never-sent, an unknown, a declined and a
  still-waiting attempt (a stored declined transaction may come back with a status outside the list, which **D-063**
  makes the `out_of_contract` anomaly: an availability cost, not a safety one); E2-B — the echoed amount form, whether
  an approved status can arrive with `IsTelAuthAbilty` true (E2-16: never read, so 001D M2's lookup phone guard is
  vacuous for this vendor), the HTTP status of an error reply; **Q-049** (the stored key is the `UniqueQuery`); the
  deployment / retention gate.

**RELEASE_PROFILE_CANDIDATE_READY_UNWIRED**
- FACT rows used: E1-07, E1-31, E1-32; for the reply E2-03, E2-04, E2-28.
- Still required before wiring: E2-B — the `PINPAD` prefix case (E1-12) and what the original commit returns after a
  release (E1-32); the release cannot be wired without the commit and the lookup.

**Optional fields deliberately unmapped:** all nine E4 keys (`provider_reference`, `approval_number`, `voucher_number`,
`deposit_id`, `card_last4`, `card_brand_code`, `pan_entry_mode`, `payment_method_code`, `provider_saved_at`), and the
never-mapped members of E2-32, E4-10 and E4-11 (section 5).

**NOT VALIDATED here:**
- Deno and the Supabase Edge runtime: not installed; the candidate is plain data and no deployed code loads it.
- Hosted behaviour, and Linux CI (no CI run exists for this branch).
- Any provider behaviour: no request was made, so the gateway's acceptance of the exact bytes and the real replies are
  unknown (E2-B).
- Any physical terminal or card.
- PostgreSQL: no pgTAP lane ran; SQL and every migration are unchanged.

**Remaining gates:** **Q-047** and **Q-049** (hard owner gates), E2-B, **Q-048**, **Q-050**, **Q-052**; 001C, 001F,
001H; [DEPLOYMENT](DEPLOYMENT.md) §18, including the retention and configuration-order steps of section 8 when the
profile is wired; the 001D merge (S14 C). Publication — any push, PR or merge of this branch and of the D-064, W1, G1
and 001E branches it stacks on — needs its own process decision.
