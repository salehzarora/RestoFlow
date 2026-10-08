# MONEY_AND_TAX_SPEC.md

> **Status — FROZEN: M0A architecture baseline, approved at RF-004.** Authored under RF-001, independently reviewed by Codex (RF-002), corrected under RF-003, and verified in a final Codex pass; the architecture freeze was **approved by the human owner, Saleh, at RF-004**. The explicit RF-001 invariants remain binding; decisions **D-001..D-028** are the frozen M0A baseline. Open questions **Q-001..Q-024** remain **Accepted Open** (per **DECISION D-027** — tracked, gating only their dependent tickets; none resolved or guessed). Changes to this frozen baseline now require the architecture-change procedure (a new ticket, independent review, and human approval). Any remaining inline pre-freeze status notes are superseded by this RF-004 approval. See [DECISIONS.md](DECISIONS.md) and [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md).

**Status:** FROZEN for M0A (RF-001) — frozen as the M0A architecture baseline at RF-004, approved into the frozen M0A baseline (RF-004).
**Owner of this topic:** This document is the single source of truth for **money representation, discounts, rounding, taxes, service charges, tips, cash handling, receipt numbering, and money-affecting audit requirements**. Other documents must reference this file rather than redefining these rules.

**Scope boundaries (ownership — do not duplicate here):**
- Entity field/column definitions live in [DOMAIN_MODEL.md](DOMAIN_MODEL.md). This document names columns conceptually and defers the canonical column list to the domain model.
- State transitions live in [STATE_MACHINES.md](STATE_MACHINES.md). This document references payment/order/shift/cash-drawer states but does not redefine transitions.
- RLS / authorization / isolation tests live in [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md).
- RPC contracts for money mutations live in [API_CONTRACT.md](API_CONTRACT.md).
- Offline outbox/inbox, idempotency mechanics, and reconciliation live in [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md).
- Printing, reprint mechanics, and Arabic/Hebrew encoding live in [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md).
- The decision log (D-xxx) lives in [DECISIONS.md](DECISIONS.md); the open-questions register (Q-xxx) lives in [OPEN_QUESTIONS.md](OPEN_QUESTIONS.md). This document cites those IDs and never invents conflicting ones.

---

## 1. Money representation (hard rule)

**DECISION D-007** — All monetary values are stored, transported, and computed as **integer minor currency units** (e.g. agorot, cents, fils). There is **NO floating-point money anywhere** — not in PostgreSQL columns, not in PostgreSQL RPC (SECURITY DEFINER) functions, not in Dart domain code, not in Drift/SQLite local storage, and not in any sync payload.

Rules:
1. Every money column is an integer type and is suffixed `_minor` (per naming **DECISION D-017**). Example conceptual columns: `unit_price_minor`, `line_total_minor`, `discount_amount_minor`, `tax_amount_minor`, `order_total_minor`, `amount_tendered_minor`, `change_due_minor`, `opening_float_minor`, `counted_amount_minor`, `variance_minor`.
2. A money value is meaningless without its currency. Any money value that can cross an organization/restaurant boundary in an API or report carries an explicit ISO 4217 currency code alongside it (see §2).
3. **SECURITY REQUIREMENT** — No client may submit a pre-computed authoritative total that the server trusts blindly. The server (PostgreSQL RPC) recomputes order totals from snapshot line data and validates client-supplied totals; a mismatch is rejected. This protects against tampering and floating-point drift originating in any client.
4. Percentages (tax rate, discount rate) are NOT money and may be stored as integer basis points (1% = 100 basis points) to avoid floating point in rate math as well. **PROPOSED DECISION — pending ChatGPT + Codex review + Saleh approval; not frozen** — basis-point representation for rates is proposed to keep all financial arithmetic in integers; this is a PROPOSED candidate (not ratified in this pass), flagged for review when Q-002 resolves.
5. All intermediate arithmetic is performed in integer minor units. Where a multiplication/division produces a fractional minor unit (e.g. percentage discounts, tax extraction), a defined rounding step (§5) converts back to an integer minor unit at a defined point in the calculation order (§9).

> **RISK R-008** — Money/rounding/tax errors before the jurisdiction is frozen. Mitigation: integer minor units (this section) plus keeping tax behaviour OPEN until Q-001..Q-004 resolve. See §6.

---

## 2. Currency scope

**DECISION D-007** sets currency at the **organization** level, overridable per **restaurant**.

- Each organization has a default currency (ISO 4217 code, e.g. `ILS`, `USD`, `AED`).
- A restaurant within the organization may override the organization default (a restaurant group may operate restaurants in different currencies).
- **Single currency per order** — an order has exactly one currency, fixed at order creation from the owning branch's restaurant currency. All line items, modifiers, discounts, taxes, service charges, payments, and the total for that order share that one currency. Mixed-currency orders are **DEFERRED** (not in MVP scope).
- The order's currency is snapshotted onto the order at creation time so a later change to the restaurant's configured currency does not retroactively alter historical orders.

> **OPEN QUESTION Q-007** — Default currency and whether multi-currency (per-order or cross-restaurant settlement) is ever required. Until resolved, MVP assumes one currency per organization/restaurant and one currency per order.

Multi-tenant note: currency configuration is tenant-scoped by `organization_id` (and `restaurant_id` for overrides). No part of money handling assumes a single organization, restaurant, or branch.

---

## 3. Price snapshots at order time

**DECISION D-008** — Orders never recompute from live menu prices. At the moment a line is added to an order, the system captures **price snapshots**:

1. **Item price snapshot** — the `unit_price_minor` of the chosen `menu_items` row (and the selected `item_sizes` / `item_variants` price, where the price derives from size/variant) is copied onto the `order_items` row.
2. **Modifier price snapshot** — the price of each selected `modifier_options` is copied onto the corresponding `order_item_modifiers` row.
3. The currency in effect (§2) is captured on the order.
4. Snapshots are immutable for the life of the order. Editing a menu price afterwards never changes an existing order; it only affects lines added after the change.

Consequences:
- Offline menu changes are safe: a line added offline uses the price snapshot known to the device at that moment; later reconciliation does not silently reprice it. Conflict handling for stale prices is governed by [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) and the per-entity conflict policy in **OPEN QUESTION Q-010**.
- Voids, refunds, and reporting all operate on snapshots, never on current menu prices.

Field-level column definitions for snapshots are owned by [DOMAIN_MODEL.md](DOMAIN_MODEL.md).

---

## 4. Discounts

Discounts exist at two levels and in two forms. Both levels operate on integer minor units and follow the rounding rules in §5.

### 4.1 Levels
- **Item-level discount** — applied to a single `order_items` line (e.g. "this dish 20% off"). Computed against that line's snapshot subtotal (item snapshot + its modifier snapshots).
- **Order-level discount** — applied to the order as a whole (e.g. "10% off the whole bill", "fixed 15.00 off").

### 4.2 Forms
- **Percentage** — expressed in integer basis points (e.g. 1000 = 10.00%). Result rounded per §5.
- **Fixed amount** — expressed directly in integer minor units; capped so a discount can never make a line or order total negative (clamped to zero — see §4.4).

### 4.3 Stacking and precedence (PROPOSED DECISION candidate)
> **PROPOSED DECISION — pending ChatGPT + Codex review + Saleh approval; not frozen** (to be ratified as a D-xxx in [DECISIONS.md](DECISIONS.md)) — Discount precedence:
1. Item-level discounts apply **first**, to each line's snapshot subtotal, producing a discounted line total.
2. Order-level discounts apply **second**, to the sum of discounted line totals (the order subtotal after item discounts).
3. Within a single level, at most **one percentage** and **one fixed** discount may stack; if both are present, the percentage applies before the fixed amount. Multiple percentage discounts on the same target are **DEFERRED** (not MVP).
4. Tax (§6) and service charge (§7) are computed **after** all discounts, on the discounted amounts, unless a frozen jurisdiction rule (Q-002) dictates otherwise.

This ordering is deterministic so the server and every offline client compute identical results.

### 4.4 Clamping and negatives
- A discount may reduce a target to exactly zero but never below zero. After applying a discount, if the computed result is negative it is clamped to `0`. *(Amended — ORDER-EDIT-001, **DECISION D-043**: this clamp caps a discount's own amount at its target when the discount is applied; it never re-clamps an order discount already stored as an absolute amount when a later change shrinks the subtotal. A sent-order edit keeps the stored `discount_total_minor` and, if it would exceed the new subtotal, is **refused** with `invalid_discount` / `discount_exceeds_order_total` — never clamped; the POS offers "Lower discount" (§9.2 M6). That is the error / detail pair `app.apply_discount` already returns, instead of flooring, when a discount would push the order's prospective `grand_total_minor` below zero ([API_CONTRACT.md](API_CONTRACT.md) §4.5). An edit does not re-apply an order-level percentage to the new subtotal either; persisting a percentage's basis is **OPEN QUESTION Q-042**.)*
- "Comp" / 100% discount is representable as a percentage discount of 10000 basis points but **requires authorization** (§4.5).

### 4.5 Authorization
- **SECURITY REQUIREMENT** — Applying a discount above a configurable per-role threshold, and any 100% comp, is a sensitive mutation performed via PostgreSQL RPC (DECISION D-011) that authorizes by membership role and records an audit event (DECISION D-013).
- Role keys permitted to authorize discounts (subject to thresholds): `manager`, `restaurant_owner`, `org_owner`. A `cashier` may apply discounts only up to a configured limit; above it requires manager authorization. Exact thresholds are configuration, owned operationally by the org; the authorization gate itself is mandatory.
- **OPEN QUESTION Q-017** — whether the `accountant` (read-only) role exists in MVP affects who can *view* discount reporting; it never grants discount authorization.
- **Sent-order edits (ORDER-EDIT-001, DECISION D-043).** The comp gate also covers an edit: an edit that takes `grand_total_minor` from > 0 to 0 — with or without a discount, for example by leaving only a zero-priced line — needs `manager` / `restaurant_owner` / `org_owner` or a `cashier` holding the default-OFF `apply_full_comp` grant, and is otherwise refused with `permission_denied` / `full_comp_permission_required`, the pair `app.apply_discount` returns for a full comp the actor may not grant (§9.2 M8). An edit never applies a new discount: added and replacement rows carry item discount `0` (§9.2 M3, M4) and the stored order discount is kept (§4.4, §9.2 M6); discounts stay with `app.apply_discount`.

---

## 5. Rounding rules

Rounding is required wherever integer minor-unit arithmetic produces a fraction (percentage discounts, percentage taxes, percentage service charges, tax extraction from tax-inclusive prices).

> **PROPOSED DECISION — pending ChatGPT + Codex review + Saleh approval; not frozen** (to be ratified as a D-xxx) — **Default rounding strategy = round half away from zero (a.k.a. commercial / "round half up" for positive amounts) to the nearest whole minor unit.** Applied per computed amount at each defined rounding point (§9), not deferred to the end. Example: 1234.5 minor → 1235; 1234.4 → 1234. This remains a PROPOSED candidate and is not ratified in this pass.

Notes and dependencies:
- The default is chosen for predictability and broad acceptability. **It is locale/jurisdiction dependent** and may be overridden once Q-001/Q-002 freeze. Some jurisdictions mandate banker's rounding (round half to even), per-line vs per-total rounding, or "cash rounding" of the final payable amount to the smallest circulating coin (e.g. rounding the grand total to the nearest 5 or 10 minor units for cash payments).
- **Cash rounding** (rounding the final payable to the nearest physical coin denomination) is a **separate, additional** step applied only to the cash-tender amount, never to the recorded order total. Whether it applies, and to what denomination, depends on jurisdiction. **OPEN QUESTION Q-002 / Q-001.** Until frozen, MVP performs no cash rounding (change is computed to the exact minor unit).
- The rounding strategy, the rounding granularity (per-line vs per-order), and any cash-rounding denomination are configuration that must be the **same** on server and all offline clients so results are bit-identical. The server is authoritative and validates (see §1 rule 3).

> **RISK R-008** applies: do not finalize rounding semantics for a real jurisdiction until Q-001..Q-004 are answered.

---

## 6. Taxes

This document owns tax *rules*; it does **not** invent jurisdiction-specific legal tax rates or fiscal requirements.

- Taxes are computed in integer minor units using integer basis-point rates and the rounding rules of §5.
- A tax is applied after discounts (§4.3) by default.
- Multiple tax components per order (e.g. a reduced-rate category alongside a standard rate) must be representable; each component records its rate and resulting `tax_amount_minor`.

> **OPEN QUESTION Q-002** — The **default tax mode is intentionally UNRESOLVED**: tax-**inclusive** (the displayed/snapshot price already contains tax, which is extracted for reporting) vs tax-**exclusive** (tax is added on top of the snapshot price). This choice, the rate(s), and category mapping depend on the jurisdiction and **block** tax freeze. MVP must support *both modes structurally* but ships no hard-coded rate.

Related blocking open questions (raise, do not answer here):
- **OPEN QUESTION Q-001** — Initial target country/jurisdiction (blocks all tax/fiscal freeze).
- **OPEN QUESTION Q-003** — Fiscal receipt/invoice legal requirements and any certified-hardware mandate.
- **OPEN QUESTION Q-004** — Legal receipt/invoice numbering rules (format, sequence-reset cadence).
- **OPEN QUESTION Q-005** — Data retention and privacy obligations affecting how long money records are kept.

**DEFERRED** — Tax-exempt customers, reverse-charge, cross-border VAT, and multi-jurisdiction tax are out of MVP scope.

> Tax-inclusive extraction formula (for when Q-002 resolves to inclusive), expressed in integers:
> `tax_amount_minor = round( gross_minor * rate_bp / (10000 + rate_bp) )`, and `net_minor = gross_minor - tax_amount_minor`. Rounding per §5. This is documented as the intended algorithm, not an active rate.

> **Sent-order edits (ORDER-EDIT-001, DECISION D-043; §9.2 M7).** An edit recomputes the tax of the **whole** order, not only of the changed lines: `tax_total_minor` is recomputed by the new `app.edit_tax_minor` from the branch's **current** tax settings on base = subtotal − order discount. Tax disabled or a 0 bp rate → `0`; `exclusive` → round half away from zero (§5) of base × rate_bp / 10000, byte-matching the POS rule (`apps/pos/lib/src/format/tax_math.dart`); `inclusive` → the edit is refused with `tax_mode_unsupported` (fail closed). No effect while tax is OFF (the branch default). No tax rate is snapshotted on the order, so a rate changed between submit and edit re-taxes the whole order at the new rate. The rate snapshot and inclusive-mode edits are **OPEN QUESTION Q-043**; the Q-002 mode choice above stays unresolved and nothing is assumed about it.
>
> **RISK R-008** — `app.add_order_items` raises the subtotal by the added lines and keeps the order's stored tax, so lines added after submit on a tax-enabled branch carry no tax. An edit's whole-order recompute corrects this on the edited order only; the general fix is MONEY-ADD-ITEMS-TAX-001, gated by Q-043.

---

## 7. Service charges

> **OPEN QUESTION Q-012** — Service-charge rules: whether a service charge applies, whether it is a percentage or fixed, the base it is computed on (pre- or post-discount, pre- or post-tax), and **whether the service charge is itself taxable**.

Design intent (structural, not a frozen rate):
- A service charge, when configured, is represented as its own line/component with `service_charge_amount_minor` in integer minor units, computed via basis-point percentage or fixed amount, rounded per §5.
- Its position in the calculation order (§9) and its taxability are configuration gated by Q-012 and Q-002.
- Service charge, if it exists, is distinct from tips (§8) and from taxes (§6).

---

## 8. Tips

> **DEFERRED** — **OPEN QUESTION Q-011.** Tips are explicitly **out of MVP scope**. No tip field is collected, computed, taxed, or reported in MVP. The schema should not bake in assumptions that would prevent adding a tips model later, but no tips behaviour ships now. Tip handling (pooling, per-employee attribution, taxability) is a future decision.

---

## 9. Canonical order total composition (calculation order)

The authoritative order total is composed in this fixed sequence. Server RPC and every offline client MUST follow it identically.

1. **Line snapshot subtotal** — for each `order_items` line: `item_snapshot_minor + sum(modifier_snapshot_minor)` × quantity (quantity is an integer count).
2. **Item-level discounts** — apply per-line (§4), clamp at zero, round per §5 → discounted line total.
3. **Order subtotal** — sum of discounted line totals.
4. **Order-level discount** — apply to order subtotal (§4), clamp at zero, round per §5.
5. **Service charge** — if configured (§7), compute on the base defined by Q-012.
6. **Tax** — compute per §6 on the post-discount (and per Q-012, possibly post-service-charge) base, in the mode chosen by Q-002.
7. **Order total** — sum of the discounted goods + service charge + tax (for tax-exclusive) **or** the discounted goods + service charge with tax shown as an extracted component (for tax-inclusive).
8. **Cash rounding** (if jurisdiction requires, §5) — applied only to the cash-payable amount at tender time, not to the stored order total.

Each amount is stored in integer minor units. The order persists its component amounts (subtotal, total discount, service charge, tax, grand total) so reports do not re-derive from menu prices (consistent with D-008).

### 9.1 Worked example (integer minor units)

Currency: minor units (e.g. cents). Tax mode for this example: **tax-exclusive at 17.00% (rate_bp = 1700)**. (Illustrative only — the real rate/mode is **OPEN QUESTION Q-002**.)

Order:
- Line A: Burger, `unit_price_minor = 4500`, modifier "extra cheese" `+700`, quantity 2.
- Line B: Soda, `unit_price_minor = 1200`, no modifiers, quantity 1.
- Item-level discount on Line A: 10% (rate_bp = 1000).
- Order-level discount: fixed `500` off.

Step 1 — line snapshot subtotals:
- Line A per-unit = 4500 + 700 = 5200; × 2 = `10400`.
- Line B per-unit = 1200; × 1 = `1200`.

Step 2 — item-level discount (Line A, 10%):
- discount = round(10400 × 1000 / 10000) = round(1040.0) = `1040`.
- Line A discounted = 10400 − 1040 = `9360`.
- Line B discounted = `1200` (no discount).

Step 3 — order subtotal = 9360 + 1200 = `10560`.

Step 4 — order-level discount (fixed 500): 10560 − 500 = `10060` (not negative; no clamp).

Step 5 — service charge: none in this example (Q-012).

Step 6 — tax-exclusive 17%: tax = round(10060 × 1700 / 10000) = round(1710.2) = `1710`.

Step 7 — order total = 10060 + 1710 = **`11770`** minor units.

Stored amounts: subtotal `10560`, total_discount `1540` (1040 item + 500 order), tax `1710`, service_charge `0`, grand_total `11770`. All integers; no floating point used at any step.

### 9.2 Sent-order edits (ORDER-EDIT-001)

**DECISION D-043** — A sent, open, unpaid order is edited **in place**: the same `orders` row keeps its id, display code, table, shift and report bucket. Each edit is one append-only, money-free `order_edits` record numbered per order (`orders.edit_count`). Retired lines become `cancelled` or `voided` and carry the provenance columns `removed_by_edit_id` / `removed_kitchen_stage`; rows written by the edit carry `edit_id`, and a row that replaces a retired line also carries `replaces_order_item_id`. No state is added (D-018). An edit is online only, through `order.edit` → `app.edit_order` ([API_CONTRACT.md](API_CONTRACT.md) §4.45), on `dine_in` / `takeaway` orders, behind the per-branch switch `order_edit_enabled` (default OFF). The change kinds are `remove`, `set_quantity`, `modify` (modifiers and note only; the line keeps its size and variant) and `add`. Columns are owned by [DOMAIN_MODEL.md](DOMAIN_MODEL.md) §2.3, §6.1, §6.2 and §6.4, line transitions by [STATE_MACHINES.md](STATE_MACHINES.md) §2.1–§2.2; the design record is [ORDER_EDIT_DESIGN.md](ORDER_EDIT_DESIGN.md) §6–§9.

An edit does not re-run the §9 sequence from scratch; it recomposes the order's stored totals over its live lines: kept lines keep their stored step 1–2 amounts (M1), rows the edit writes are priced by step 1 with item discount `0` (M3, M4), step 3 is re-rolled (M5), step 4 is **not** re-run — the stored order discount is kept as an absolute amount and never clamped (M6) — and step 6 is re-run for the **whole** order from the branch's current tax settings (M7). Money rules (integer minor units throughout, D-007):

- **M1** Kept lines are untouched: their rows, modifiers, snapshots, item discount and legacy pricing epoch (D-008).
- **M1a** **Legacy-price predicate.** MONEY-PRICING-FORMULA-002A moved line totals to the §9 step 1 per-unit formula without adding a pricing-epoch column, so rows stored before it may carry the older amount (option surcharges counted once per line instead of once per unit). "Legacy" is therefore derived from the stored row only, never from a timestamp or a new column: a line L is **legacy-priced** iff `L.line_total_minor + L.line_discount_minor <> L.quantity × (L.unit_price_minor_snapshot + COALESCE(Σ m.price_minor_snapshot × m.quantity over L's order_item_modifiers, 0))`. A row on which the two epoch formulas agree (quantity 1, or no priced modifiers) is not legacy and is editable, because the M3 recomputation reproduces its stored amount exactly. The predicate is computed **server-side only**: `app.edit_order` (refusal `legacy_line_not_editable`) and `app.pos_order_detail` (the per-item `legacy` boolean) evaluate the same SQL expression through one internal helper; the POS never recomputes it and only reads the flag.
- **M2** Retired lines keep their row and amounts for history; their status (`cancelled` / `voided`) excludes them from every sum.
- **M3** Continuation, replacement and delta rows copy **server-side** from the old row the base price, the size / variant and name snapshots, the display-order snapshots and every kept option's price and name snapshots. The display-order snapshots are restored by an UPDATE after the insert, because the MENU-ORDER-001 BEFORE INSERT triggers always re-derive them from the live menu; the triggers are not changed. The item `prep_snapshot` and each kept option's `meat_snapshot` are copied frozen, except that each `classifier_selected` is re-answered by the presence of its `classifier_option_id` in the replacement's full option set (the `app.trusted_modifier_prep_snapshot` / `app.trusted_item_prep_snapshot` presence rule, applied to the frozen link and never to the live menu). Only newly chosen options carry a client snapshot; it passes the option ownership check and the prep-staleness check, the latter against the replacement's full modifier array. Every new row is priced `line_total_minor = quantity × (unit_price_minor_snapshot + Σ option price_minor_snapshot × option quantity)` — the §9 step 1 per-unit formula — with item discount `0`. Lines with an item discount (`line_has_discount`) or a legacy price (M1a, `legacy_line_not_editable`) can only be removed.
- **M4** Added lines follow `app.add_order_items` exactly: the current menu price, snapshotted when the line is added (§3, D-008), and its checks; an `add` carries `line_discount_minor` `0`. Sellable / available is checked under the lock for adds, quantity increases and a modify that raises the total quantity. A size or variant change is a `remove` plus an `add`, priced at the current menu price.
- **M5** `subtotal_minor` is **re-rolled** as the sum of live line totals, never adjusted by a delta, so gross − item discount − order discount = net in reports (§13).
- **M6** `discount_total_minor` keeps its stored absolute amount; it is never clamped (§4.4) and never re-derived from a percentage (**OPEN QUESTION Q-042**). If it would exceed the new subtotal the edit is refused with `invalid_discount` / `discount_exceeds_order_total` and the POS offers "Lower discount". The audit records the effective discount ratio before and after.
- **M7** `tax_total_minor` is recomputed by the new `app.edit_tax_minor` from the branch's **current** tax settings on base = subtotal − discount: tax disabled or a 0 bp rate → `0`; `exclusive` → round half away from zero (§5) of base × rate_bp / 10000, byte-matching `apps/pos/lib/src/format/tax_math.dart`; `inclusive` → `tax_mode_unsupported` (fail closed). No effect while tax is OFF (the branch default). The recompute also corrects earlier untaxed add-items lines on that order (§6, **RISK R-008**). Tax-rate snapshot and inclusive tax: **OPEN QUESTION Q-043**.
- **M8** `grand_total_minor` = subtotal − discount + tax ≥ 0. **Zero-out guard:** if the total goes from > 0 to 0, the caller needs `manager` / `restaurant_owner` / `org_owner` or the `apply_full_comp` capability, with or without a discount (refusal `permission_denied` / `full_comp_permission_required`, the pair `app.apply_discount` already emits, §4.5); otherwise a cashier could leave a zero-priced line and let the order auto-complete unpaid. An edit that would leave no live line is refused (`edit_would_empty_order`); cancelling the order stays `app.void_order`.
- **M9** The `expected` totals (`subtotal_minor`, `tax_total_minor`, `grand_total_minor`) are mandatory (`expected_totals_required`); any mismatch → `totals_mismatch` with the server's figures, nothing written (§1 rule 3).
- **M10** A live completed payment → `order_already_settled`. Paid orders need the deferred refund flow (D-023, D-024, §12.3).
- **M11** Every edit bumps `orders.revision`, so a payment prepared against the old total (payments send `expected_revision`) gets `40001` and re-reads the new total. The kitchen acknowledgement (`app.kitchen_ack_order_edit`, D-044) never bumps revision.
- **M12** `receipt_number` (D-021, §15), shift expected cash (§14) and the order's report bucket (`created_at`) are unaffected. `order_edits`, service rounds and kitchen payloads carry no money (T-003).
- **M13** Reporting (amends §12.2 "Money effect" and §13 for edit-retired lines only). Lines retired by an edit (`removed_by_edit_id` set, status `voided` or `cancelled`) are excluded from Gross sales, Discounts and Net sales, and from the **Voids** bucket, which covers voided orders — orders with status `voided` (`void_count`, `void_total_minor`); an order voided whole after an edit still reports its full grand total there — and item voids not made by an edit (today the only such item voids are the cascade of a whole-order void, so the bucket stays order-level, as D-043 point 10 states). They are never silently dropped: they are reported in a separate **Order edits** bucket for each tenant scope and business day, on the order's `created_at` bucket (M12), whose figures are defined in §13 (`edit_count`, `edited_order_count`, `removed_minor`, `replaced_out_minor`, `replaced_in_minor`, `added_minor`, `net_change_minor`), each also broken down by `reason_code` and by employee. The gross retired value (`removed_minor` + `replaced_out_minor`) is always shown, so the gross amounts stay visible as §12.2 requires; net of replacements is a derived column and never replaces the gross figure.

Every refusal above is RETURNed (error / detail), audited as `order.edit_denied` and decided before the first write, so a refused edit changes no money. Every applied edit writes one append-only `order.edited` audit event (§17, D-013) carrying the old and new totals, the effective discount ratio before and after, the reason and the per-line before / after quantities and totals; a `remove`, a `modify` or a quantity reduction requires a reason (`reason_required`; `other` needs text).

**Worked example (integer minor units; tax off, no discount).**

Order before the edit:
- Line A: Burger, `unit_price_minor = 4000`, options Tomato and Cucumber (both `+0`), quantity 1 → `4000`.
- Line B: Fries, `1500`, quantity 1.
- Line C: Cola, `800`, quantity 1.
- Subtotal `6300`; grand total `6300`.

Edit (one `order.edit`; a reason is required because a line is removed and one is modified):
- `modify` Line A, burger without tomato: Line A is retired and a replacement row with Cucumber only (`replaces_order_item_id` = Line A) is priced from Line A's copied snapshots (M3) → `4000`.
- `remove` Line B: retired.
- `add` Lemonade at the current menu price, `900` (M4).

After the edit: subtotal re-rolled = 4000 + 800 + 900 = `5700` (M5); discount `0`; tax `0` (tax OFF, M7); grand total `5700`. The `expected` totals sent are subtotal `5700`, tax `0`, grand total `5700` (M9), and `orders.revision` is bumped (M11).

Reports: this order's Gross and Net count only its live lines (`5700`). Order edits bucket: `removed_minor` `1500` (fries), `replaced_out_minor` `4000` / `replaced_in_minor` `4000` (burger changed), `added_minor` `900` (lemonade), `net_change_minor` = 4000 + 900 − 1500 − 4000 = `−600` = 5700 − 6300, matching the `order.edited` audit 6300 → 5700. The Voids bucket is unchanged.

---

## 10. Cash received & change due

- At cash tender, the cashier records `amount_tendered_minor` (integer). `change_due_minor = amount_tendered_minor − payable_minor` where `payable_minor` is the grand total (after any jurisdiction cash rounding, §5/§8 cash-rounding note).
- `change_due_minor` is never negative for a completed cash payment; if tendered < payable, the payment is not completable as a single full cash tender (split/partial tender handling is governed by the Payment state machine and is otherwise **DEFERRED** beyond simple single-tender + change in MVP unless prioritized).
- All cash amounts are integer minor units. No floating point.
- Cash tendered/change are inputs to cash reconciliation (§14).

Payment states are owned by [STATE_MACHINES.md](STATE_MACHINES.md): `pending -> tendered -> completed`; plus `voided`, `failed`; `refunded` is **DEFERRED**. This document references those states and does not redefine them. Per **DECISION D-023**, `completed` is **TERMINAL** and `completed -> voided` is **FORBIDDEN**; payment void exists **only pre-completion** (`pending -> voided`, `tendered -> voided`). See §11.

---

## 11. Payment status (reference)

Money-affecting payment actions are bound to the **Payment** state machine (DECISION D-018), defined in [STATE_MACHINES.md](STATE_MACHINES.md), which **owns** these transitions; this document references them and does not redefine them:
- `pending -> tendered -> completed` (terminal: `completed`).
- `voided`, `failed` (terminal).
- `refunded` is **DEFERRED** until the payment model is frozen (§12.3).

**DECISION D-023** — `completed` is **TERMINAL** in MVP. Payment **void exists ONLY pre-completion**: the only permitted void transitions are `pending -> voided` and `tendered -> voided`. The transition `completed -> voided` is **FORBIDDEN** — there is no post-completion void/reversal mechanism in MVP. A `tendered -> voided` void (a pre-completion void) must account for any cash physically received before finalization (see §12.2). Refunds/reversals/post-completion corrections are **DEFERRED** (§12.3); MVP provides no hidden refund path and no "post-completion reversal via `completed -> voided`".

Money totals attach to the order; payment rows attach to the order and record method, `amount_minor`, currency, and status. Sensitive payment mutations (pre-completion void, future refund) go through RPC (D-011) and are audited (D-013).

---

## 12. Void vs cancellation vs refund (distinct definitions)

These three are **distinct** and must never be conflated. They map to the PROPOSED state enumerations (D-018; approved into the frozen M0A baseline (RF-004) — RF-001 §8 directs us to evaluate, not assume final).

### 12.1 Cancellation
- **Definition:** Ending an order (or item) **before production / before it became financially binding**.
- **Order:** `cancelled` is a **pre-production, terminal** state. An order may be cancelled from `draft`/`submitted`-stage states before kitchen production.
- **Order item:** `cancelled` is terminal (pre-production).
- **Money effect:** No completed payment exists; nothing to reverse. No refund. Recorded for audit and reporting (cancelled orders are excluded from net sales — §13).

> **DECISION D-024** — `order.completed` is **TERMINAL**. Cancelling or voiding an order that **already has a COMPLETED payment is REJECTED in MVP**: doing so would require returning money, which would need the deferred refund flow (§12.3). Historical `completed` order and payment records are **never rewritten** to simulate a refund or reversal. Order cancellation/void is therefore confined to states with no completed payment.

### 12.2 Void
- **Definition:** Reversing an order/item/payment **after it was submitted / became financially relevant**, requiring authorization and a reason.
- **Order:** `voided` is a **post-submission, terminal** state requiring authorization + reason (D-018).
- **Order item:** `voided` terminal.
- **Payment:** `voided` is terminal and is a **pre-completion** void only — **DECISION D-023** permits `pending -> voided` and `tendered -> voided`, but **`completed -> voided` is FORBIDDEN**. There is **no** post-completion void/reversal in MVP. A `tendered -> voided` void must **account for any cash physically received before finalization** (the cash received is reconciled/returned operationally and recorded in the audit event; it is not silently dropped).
- **Authorization & audit:** **SECURITY REQUIREMENT** — A void (especially voiding an *unpaid but submitted* order, or a pre-completion payment) is a sensitive mutation via RPC (D-011); the actor must hold an authorizing role (e.g. `manager`+) and supply a reason; an append-only audit event is written (D-013). The canonical isolation/permission test "a cashier cannot void a paid order without permission" (SECURITY_AND_THREAT_MODEL.md) governs enforcement. *(Amended — ORDER-EDIT-001, **DECISION D-043**: a line `cancelled` / `voided` by a sent-order edit on an **unpaid** order is authorized for a `cashier` by the existing default-ON, deny-only `void_order` capability rather than a `manager`+ role; the edit always carries a reason (`reason_required`) and is audited `order.edited` (§9.2). On KDS branches the per-branch `order_edit_finished_food_manager_only` switch (default OFF) restricts Ready / Served lines to `manager`+; a standalone item void stays `manager`+. The capability is owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) §5.)*
- **Offline posture:** voids are **online-only by default** (per the STATE_MACHINES Shift/Order ASSUMPTION). Offline-provisional voids are a deferred/open consideration, not the default behaviour.
- **Money effect:** Removes the voided (pre-completion) amounts from net sales; the gross/void amounts remain visible for audit and reporting (§13). Money on a `completed` payment cannot be reversed by a void — see §12.3. *(Amended — ORDER-EDIT-001, **DECISION D-043**: a line retired by a sent-order edit — `removed_by_edit_id` set, status `voided`, or `cancelled` (§12.1) when its work unit was still `submitted` on the KDS channel — is likewise removed from net sales, but its gross amount stays visible in the **Order edits** bucket (§13) rather than in Voids (§9.2 M13). Edits apply to unpaid orders only (`order_already_settled`, §9.2 M10).)*

### 12.3 Refund
- **Definition:** Returning money to a customer for a **completed** payment.
- **Status:** **DEFERRED.** The Payment `refunded` state is DEFERRED (D-018) until the payment model is frozen. No refund flow, partial refund, or refund-to-original-tender logic ships in MVP. There is **NO MVP mechanism** for returning money on a completed payment.
- **No hidden reversal:** Per **DECISION D-023**, MVP has **no** post-completion money-reversal path. A refund is **NOT** implemented as a `completed -> voided` transition (that transition is FORBIDDEN — §11, §12.2) and there is no other hidden refund mechanism. Historical `completed` payment and order records are **never rewritten** to simulate a refund or reversal.
- **Why deferred:** Refunds depend on the frozen payment/settlement model and on jurisdiction fiscal rules (Q-002/Q-003/Q-004). Do not implement refunds before those freeze.
- **Interim guidance:** In MVP, money already *completed* cannot be returned through the app; correcting a completed payment is out of scope and must be handled operationally until the refund model is designed.

---

## 13. Sales totals composition

Reports compose from persisted, snapshot-based amounts (D-008), in integer minor units, grouped by tenant scope (`organization_id`, then `restaurant_id`, `branch_id`, and where relevant `station_id`/`device_id`). Reporting detail is owned operationally; the **definitions** of the money buckets are owned here:

- **Gross sales** = sum of line snapshot subtotals before discounts, for orders that reached a sale-relevant state.
- **Discounts** = sum of item-level + order-level discount amounts.
- **Net sales** = gross sales − discounts (excludes tax and service charge), excluding **cancelled** orders entirely and **excluding voided** amounts.
- **Service charge total** = sum of `service_charge_amount_minor` (Q-012 gated).
- **Tax total** = sum of `tax_amount_minor` (mode/rate per Q-002); for tax-inclusive mode this is the extracted tax.
- **Voids** = sum of voided amounts, reported separately (not part of net sales) for audit/loss-prevention. *(Amended — ORDER-EDIT-001, **DECISION D-043**: Voids covers voided orders — orders with status `voided` (`void_count`, `void_total_minor`); an order voided whole after an edit still reports its full grand total here — and item voids not made by an edit (today only the cascade of a whole-order void, so the bucket stays order-level). Lines with `removed_by_edit_id` are reported only in **Order edits** below, never here.)*
- **Order edits** *(ORDER-EDIT-001, **DECISION D-043**; §9.2 M13)* = the lines retired by sent-order edits (`removed_by_edit_id` set, status `voided` or `cancelled`) and the rows those edits wrote, reported for each tenant scope and business day on the order's `created_at` bucket (§9.2 M12). Retired lines are excluded from Gross sales, Discounts, Net sales and Voids. Figures, all integer minor units except the counts:
  - `edit_count` and `edited_order_count`;
  - `removed_minor` = Σ `line_total_minor` of retired lines with no replacement row;
  - `replaced_out_minor` = Σ `line_total_minor` of retired lines that a row with `replaces_order_item_id` replaces;
  - `replaced_in_minor` = Σ `line_total_minor` of those live replacement or continuation rows (every continuation — a reduction's remainder or an unchanged modify replacement — and every modify replacement carries `replaces_order_item_id`; increase deltas and added lines carry none);
  - `added_minor` = Σ `line_total_minor` of live rows with `edit_id` set and no `replaces_order_item_id` (added lines and +N delta rows);
  - `net_change_minor` = `replaced_in_minor` + `added_minor` − `removed_minor` − `replaced_out_minor`.

  Each figure is also broken down by `reason_code` and by employee. The gross retired value (`removed_minor` + `replaced_out_minor`) is always shown, so the gross amounts stay visible (§12.2); net of replacements is a derived column and never replaces the gross figure. The reader is `owner_order_edits` ([API_CONTRACT.md](API_CONTRACT.md) §4.47, ORDER-EDIT-001G).
- **Collected (tendered) total** = sum of `amount_minor` on `completed` payments.

Rule: voided and cancelled transactions are **never** silently dropped — they are reported in their own buckets so totals reconcile and shrinkage is visible. All buckets are integer minor units in the order/report currency (single currency per order, §2). *(Amended — ORDER-EDIT-001, **DECISION D-043**: lines retired by a sent-order edit are likewise never silently dropped; their own bucket is **Order edits**, not Voids.)*

---

## 14. Cash reconciliation

Cash reconciliation ties cash movements to the **Shift** and **Cash drawer session** state machines (D-018, owned by [STATE_MACHINES.md](STATE_MACHINES.md)). This section owns only the money math; the state transitions are referenced, not redefined.

**DECISION D-028** — **Close/count and reconciliation are two SEPARATE steps with distinct authorization:**
- **Close / count** (`close_shift`) — performed by the **`cashier`** (or an **authorized `manager`**): the drawer is counted and the counted amount and variance are recorded against the shift/drawer.
- **Reconciliation** (`reconcile_shift`) — performed by a **`manager`, `restaurant_owner`, or `org_owner`**: a separate review/sign-off step that accepts the counted result and variance.
- These are distinct mutations and must not be collapsed into one. The **`accountant` is read-only** (Q-017) and performs **neither** mutation — it may only view reconciliation reporting.
- Variance arithmetic is owned **here** (this document): `variance = counted − expected` (see below).

- Cash drawer session lifecycle: `opened(opening float) -> active -> counting -> closed(counted + variance) -> reconciled`; bound to a shift. Shift lifecycle: `opening -> open -> closing -> closed -> reconciled`.
- **Opening float** (`opening_float_minor`) is recorded at drawer open (integer).
- **Expected cash** = `opening_float_minor + cash_sales_minor − cash_refunds_minor (DEFERRED, 0 in MVP) − paid_out_minor + paid_in_minor`. Pay-in/pay-out (cash drops, petty cash) representation is referenced from the shift/drawer model; all in integer minor units. The conceptual `expected_cash_minor` value maps to the `expected_total_minor` column owned by [DOMAIN_MODEL.md](DOMAIN_MODEL.md) (this document does not redefine that column).
- **Counted cash** (`counted_amount_minor`) is entered at count.
- **Variance** (`variance_minor`) = `counted − expected` (i.e. `counted_amount_minor − expected_cash_minor`), signed minor units; may be negative (shortage) or positive (overage). This document is the single owner of the variance-sign definition; STATE_MACHINES.md cites this rule rather than restating the arithmetic.
- A non-zero variance must be recorded and is auditable (D-013); closing/reconciling a drawer with a variance does not delete the variance — it preserves it.
- All cash reconciliation math is integer minor units; no floating point.

---

## 15. Receipt numbering

**DECISION D-021** — Receipt numbering is a **per-branch monotonic, server-assigned sequence**.

- Each `branches` row has its own monotonically increasing receipt sequence; numbers do not collide across branches, restaurants, or organizations (tenant-scoped by `organization_id`/`restaurant_id`/`branch_id`).
- The **authoritative** receipt number is assigned by the server.
- `branches.receipt_prefix` is a **display/format adornment** layered over the authoritative per-branch monotonic sequence; it is not itself the sequence and does not affect uniqueness or ordering. The final legal receipt format (including any prefix rules) remains gated by **OPEN QUESTION Q-004**.
- **Offline provisional id:** when a device is offline, it assigns a clearly-marked **provisional** local identifier so a receipt can print immediately; on sync the provisional id is **reconciled** to the authoritative server-assigned per-branch number. The reconciliation/reprint flow (a corrected receipt may need reprinting with the authoritative number) is governed jointly by [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md) and [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md).
- **DECISION D-022** — every mutating client operation (including the operation that finalizes a receipt) carries an **idempotency key = `device_id` + `local_operation_id`**, so a retried sync never assigns two authoritative numbers to the same logical receipt and never duplicates a payment.

> **OPEN QUESTION Q-004** — Legal numbering rules (mandatory format, whether the sequence must reset daily/annually, gap-free legal requirements) are **jurisdiction-dependent and unresolved**. The per-branch monotonic design is the technical baseline; legal formatting/reset is applied once Q-001/Q-004 freeze. **OPEN QUESTION Q-003** (certified fiscal hardware) may further constrain how numbers are issued.

---

## 16. Reprinting

- A receipt or ticket may be **reprinted**; a reprint must record a **reason** and write an append-only audit event (D-013) capturing actor, device, organization/restaurant/branch, timestamp, the receipt identifier, and the reason. Reprints should be visibly marked as a reprint (e.g. a "REPRINT" / "DUPLICATE" indicator) to deter fraud.
- The reprint **mechanics, formatting, marking, and Arabic/Hebrew encoding/raster fallback** are owned by [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md) (see also Q-015). This document owns only the requirement that every reprint of a money document is audited with a reason.
- **SECURITY REQUIREMENT** — reprinting a receipt must not allow editing of any monetary amount; it reproduces the snapshot-based, already-finalized figures.

---

## 17. Audit requirements for money-affecting actions

**DECISION D-013** — All money-affecting actions write **append-only audit events** that are never updatable or deletable by application roles. Audit-event structure and the audit table are owned by [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md) / [DOMAIN_MODEL.md](DOMAIN_MODEL.md); this document enumerates **which** money actions MUST be audited and **what minimum detail** they carry.

Mandatory audited money actions:
1. Applying/changing a discount (item or order level), with old/new amounts and the authorizing actor.
2. Voiding an order, item, or payment (with reason — mandatory).
3. Cancelling an order/item.
4. Completing a payment / recording tender and change.
5. Opening a drawer (opening float), counting, closing (with variance), and reconciling.
6. Assigning/reconciling a receipt number (provisional → authoritative).
7. Reprinting a receipt (with reason, §16).
8. Any override above a role threshold (comp, large discount, manual price override if ever introduced).
9. (Future) Refunds — DEFERRED with the refund model (§12.3).

Each audit event records at minimum (per D-013): actor (user identity + membership), device, `organization_id`, `restaurant_id`, `branch_id`, timestamp (client and server), action, reason (where applicable), old values, and new values. Money values in audit events are integer minor units.

> **SECURITY REQUIREMENT** — Sensitive money mutations (voids, threshold-exceeding discounts, comps, future refunds) execute via PostgreSQL RPC (SECURITY DEFINER, DECISION D-011) which authorizes by membership role/scope and writes the audit event atomically with the mutation. No service-role credential is ever embedded in any Flutter client (D-011).

---

## 18. Multi-tenant & offline guarantees (summary)

- Every money record is tenant-scoped by `organization_id` (DECISION D-001) plus `restaurant_id`/`branch_id`/`device_id`/`station_id` where relevant (D-002). No money logic assumes a single organization/restaurant/branch.
- No shared accounts: every money-affecting action is attributable to an individual user identity via a membership-scoped role (D-004/D-005) acting on a paired, authorized device.
- Offline: money is computed locally on snapshots (§3) using the identical, server-mirrored calculation order (§9) and rounding config (§5); the server re-validates on sync (§1 rule 3); idempotency keys (D-022) prevent duplicate payments/receipts; reconciliation rules live in [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md).

---

## 19. Open questions and deferrals referenced by this document

- **OPEN QUESTION Q-001** — Target jurisdiction (blocks tax/fiscal/numbering freeze).
- **OPEN QUESTION Q-002** — VAT/tax rates; tax-inclusive vs tax-exclusive default.
- **OPEN QUESTION Q-003** — Fiscal receipt/invoice legal requirements & certified hardware.
- **OPEN QUESTION Q-004** — Receipt/invoice numbering legal rules (format, reset).
- **OPEN QUESTION Q-005** — Data retention & privacy obligations for money records.
- **OPEN QUESTION Q-007** — Default currency; single vs multi-currency.
- **OPEN QUESTION Q-010** — Per-entity conflict-resolution policy (affects stale-price/discount conflicts).
- **OPEN QUESTION Q-012** — Service-charge rules & taxability.
- **OPEN QUESTION Q-017** — Whether `accountant` (read-only) ships in MVP (affects money-report visibility, never authorization).
- **OPEN QUESTION Q-042** — Persisted percentage-discount basis, so a sent-order edit can re-apply a percentage (v1 keeps the stored absolute amount; §4.4, §9.2 M6).
- **OPEN QUESTION Q-043** — Tax-rate snapshot on orders, and `inclusive` tax for sent-order edits (v1 refuses with `tax_mode_unsupported`; §6, §9.2 M7).
- **DEFERRED** — Tips (Q-011), Refunds (payment `refunded`), multi-currency orders, cash rounding (until jurisdiction frozen), partial/split tender beyond single-tender + change.

## 20. PROPOSED DECISION candidates raised here (for ratification in DECISIONS.md)

These are **PROPOSED DECISIONS — pending ChatGPT + Codex review + Saleh approval; not frozen** in this pass:

1. Default rounding strategy = round half away from zero, applied per computed amount at each rounding point (§5).
2. Discount precedence: item-level before order-level; one percentage + one fixed per level; percentage before fixed; clamp at zero (§4.3).
3. Rates represented as integer basis points to keep all financial arithmetic integer-only (§1.4).

These are flagged as PROPOSED candidates and must be formally adopted (assigned D-xxx IDs) in [DECISIONS.md](DECISIONS.md) after review and human approval, before any implementation freeze; they do not override any existing D-xxx and are not ratified here.
