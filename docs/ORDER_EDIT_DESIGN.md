# ORDER-EDIT-001 — Editing a sent, open order (design and decision record)

> **Working design note for Work ID ORDER-EDIT-001.** This is NOT a frozen baseline
> document. It records the owner's approval of the feature and the full design that
> the implementation slices (§10) build against. It cites the frozen sources of truth
> — [DECISIONS.md](DECISIONS.md), [STATE_MACHINES.md](STATE_MACHINES.md),
> [API_CONTRACT.md](API_CONTRACT.md), [MONEY_AND_TAX_SPEC.md](MONEY_AND_TAX_SPEC.md),
> [OFFLINE_SYNC_SPEC.md](OFFLINE_SYNC_SPEC.md),
> [PRINTERS_AND_HARDWARE_SPEC.md](PRINTERS_AND_HARDWARE_SPEC.md),
> [SECURITY_AND_THREAT_MODEL.md](SECURITY_AND_THREAT_MODEL.md),
> [DOMAIN_MODEL.md](DOMAIN_MODEL.md) — and amends them only through the entries listed
> in §12, which take effect only when transcribed under the architecture-change
> procedure.
>
> **Update 2026-10-08 — rule (c) invoked.** The owner instructed ORDER-EDIT-001 not to
> wait for #288. The labels were re-verified under rule (b): all are still free on main
> and on #288 head `9d817a34`. They were then written directly on main by the
> ORDER-EDIT-001 register-transcription PR: D-043, D-044, Q-042..Q-046, TH-7, T-019 and
> API_CONTRACT §4.45–§4.47. The D-040..D-042 / Q-031..Q-041 / T-018 / §4.43–§4.44 gaps
> are recorded there as held by open PR #288. Once the transcription PR merges, the
> owning documents carry the decision record, and the §10 slices may move to Ready in
> dependency order. #288's branch is never touched by ORDER-EDIT work. Where the
> register tails meet, #288 brings main into its branch (merge or rebase, its own
> choice, as rule c anticipates). It keeps both sides, putting its own entries first
> and dropping the "held by #288" notes. The paragraphs below are the
> pre-transcription record and are kept unchanged.
>
> **Register entries are proposed, not yet written; their IDs are provisional.** Open
> PR #288 (STOREFRONT-PUBLISH-001, head `9d817a34`, last updated 2026-09-27) holds
> D-040..D-042, Q-031..Q-041, T-018 and API_CONTRACT §4.43–§4.44. It is an
> integration branch whose sub-PRs (#289–#292) keep allocating IDs, and its own
> DECISIONS.md says the next free ID is **D-043+**. This note therefore uses the
> **provisional** labels D-043, D-044, Q-042..Q-046, threat row TH-7 and test T-019
> (SECURITY_AND_THREAT_MODEL §13 / §14) and API_CONTRACT §4.45–§4.47. No other D-ID is
> claimed by this change. Only the owning registers allocate IDs (AGENT_WORKFLOW §9
> step 3), so these labels are claims, not reservations. Rules:
>
> - **(a)** When this note's PR (#302) opens, an information-only comment on PR #288
>   names these labels as claimed by ORDER-EDIT-001 (owner-approved 2026-10-08). It
>   requests no change to #288; a collision is resolved on the ORDER-EDIT side by
>   rule (b), so #288's work is not affected.
> - **(b)** At transcription, the registers are re-read on main and on every open PR.
>   If any label is already taken, ORDER-EDIT-001 takes the next free IDs instead and,
>   in the same docs commit, renumbers every citation in this note and on any
>   ORDER-EDIT branch.
> - **(c)** The owner set no fixed fallback date (2026-10-08): ORDER-EDIT-001 waits for
>   #288. If the owner later instructs it explicitly, ORDER-EDIT-001 writes its
>   entries directly on main without waiting for #288. The
>   D-040..D-042 / Q-031..Q-041 / T-018 / §4.43–§4.44 gap is recorded as held by #288,
>   the way D-030 is recorded as reserved, and #288 rebases onto it.
>
> §12 is an **outline** of those entries, not text ready to paste into the registers;
> their substance is §2 and §6–§9 of this note. The register text is written in its
> own docs PR under ORDER-EDIT-001: full ADR blocks (Status, Context, Decision,
> Alternatives considered, Consequences, Related), a DECISIONS changelog line with the
> new range and next free ID, fully filled Q rows per D-027, the TH-7 row and T-019
> test, the drafted §4.45–§4.47 contract blocks, and the STATE_MACHINES, MONEY,
> DOMAIN_MODEL, SECURITY §5 and OFFLINE_SYNC amendments. Under AGENT_WORKFLOW §9 steps
> 3–5 that PR gets independent read-only review and the owner's approval, and
> ORDER-EDIT-001 is Done only when it is merged to main. Under §9 step 6 and DoR items
> 4–5, **no §10 slice other than slice 0 moves to Ready before then** — including
> KITCHEN-DISPATCH-HARDEN-001 and POS-ORDER-DETAIL-IDS-001, which implement parts of
> D-044 and of the `pos_order_detail` contract. Until then this note is the
> owner-approved design proposal for the feature, not the decision record: the owning
> documents stay authoritative for every topic they own.
>
> The design was produced from a verified map of the current code (main @ `86a3e247`),
> three independent designs, a four-lens review (owner goals, integrity and money,
> kitchen operations, delivery risk) and an independent review of this note. Evidence
> paths below are to that commit.

---

## 1. The request

In the POS, an order cannot be changed once it reaches the kitchen. Customers change
their minds ("the burger without tomato", "remove the fries", "one more cola"). The
owner wants the cashier to be able to **edit any open, unpaid order normally**, even
after it was sent to the kitchen, with prices recalculated and the kitchen told at
once.

The owner's first idea was to silently cancel the old order (not recorded as a
cancelled order) and send a new order with the **same order number** carrying the
change, which the kitchen then cooks and prints as normal.

## 2. Verdict on delete-and-recreate (rejected)

The goals are right; the mechanism cannot work here and is unsafe.

1. **A new order cannot carry the same number.** The `#XXXXXX` code is the last six
   hex characters of the order's UUID
   (`packages/domain/lib/src/order/display_order_code.dart`; the same expression in
   SQL). There is no order-number column, and `receipt_number` (D-021) is only
   assigned at payment. "Same number" therefore means "same order row". Minting a new
   UUID with the same tail would only counterfeit the code: two different orders
   would share it in history, audit and tickets.
2. **The old order cannot disappear.** DELETE is revoked and denied by RLS
   (`orders_del_deny`, `order_items_del_deny`); child rows reference orders
   `ON DELETE RESTRICT`; audit is append-only (D-013) and already holds
   `order.submitted`; deletion is a tombstone or a state change only (D-020); voided
   amounts are never silently dropped (MONEY §13).
3. **The only legal way to retire it is a void** — exactly the "cancelled order" the
   owner wants to avoid: a red PSC-001D card on the KDS that must be acknowledged, a
   `*** VOID ***` slip on printer-only branches, and `void_count` in the reports.
4. **It is harmful in the kitchen.** A full re-send after cooking has started is
   either cooked twice or the removal is missed; printed paper cannot be recalled.
5. **It is the classic cashier fraud pattern** (take the cash, then rewrite the bill),
   which D-013, D-020 and MONEY §13 exist to close.

What we keep from the owner's idea: the same order and number, normal editing,
recalculated prices, the kitchen told at once, and **never a "cancelled order"**.
When the kitchen has not yet acknowledged a ticket, it is updated in place (the
kitchen still confirms the change, owner decision 3), which is his "fresh ticket"
done safely. The one goal deliberately not met is "no record": every edit is recorded
as an **order edit**, never as a cancellation.

## 3. Decision summary (proposed D-043 and D-044; outline in §12)

**D-043 — a sent-order edit is an in-place delta edit of the SAME open, unpaid order.**
Each edit is one append-only, money-free `order_edits` record numbered per order; the
order keeps its row, UUID, code, table, shift and report bucket. Lines are retired
(cancelled/voided with edit provenance) and replaced or added; no new states are
introduced (D-018 enumerations unchanged). Online only, unpaid only, behind a
per-branch switch (default OFF).

**D-044 — the kitchen is told precisely.** On KDS branches the affected ticket is
flagged CHANGED (removed lines struck through, changed lines "was → now", new lines
badged) and the kitchen confirms every change with one tap ("Got it"). On
printer-only branches the cashier's POS prints one change slip at once: the changes
plus the complete current order.

## 4. Owner decisions (2026-10-08)

| # | Question | Owner's answer |
|---|---|---|
| 1 | Replace delete-and-recreate with an in-place edit of the same order (same number, recorded as an edit, unpaid orders only)? | **Approved.** |
| 2 | Who may remove or change food that is already Ready or Served? | **Any cashier allowed to cancel orders** (the existing default-ON `void_order` capability), with a required reason and per-cashier reporting. The per-branch switch "Only managers may remove food that is Ready or Served" exists and defaults **OFF**. |
| 3 | Must the kitchen confirm every change on the KDS? | **Yes, every change to a ticket on screen** — including a ticket not yet acknowledged, because cooks often start before tapping Acknowledge. The owner stressed that **some restaurants run without a kitchen screen**: that is the existing branch setting `kitchen_workflow_mode = 'printer_only'`, where there is no confirmation step and the change slip prints at once (§7). |
| 4 | What does the printer-only change slip contain? | **The changes plus the full "ORDER NOW" list** on one slip, footer "Replaces earlier tickets for #code". |

Defaults confirmed by the owner on 2026-10-08 ("go with the defaults"; reversible later):

- **Tax:** an edit recomputes the whole order's tax at the branch's current rate. No
  effect while tax is OFF (the branch default). An `inclusive` tax mode is refused
  (fail closed). See M7 and Q-043.
- **Discount:** an order discount keeps its stored shekel amount. If it would exceed
  the new subtotal the edit is refused and the POS offers "Lower discount"; it is
  never silently clamped. Re-applying a percentage is Q-042.
- **Finished food on printer-only branches:** with no kitchen screen the system cannot
  tell whether food is cooked. Direct-print orders and lines are stored as `served`
  at submit (`20260729090000_kitchen_print_dual_001c_direct_print_dispatch.sql:106-118`),
  but every paper line counts as stage "printed". So the "Only managers may remove
  food that is Ready or Served" switch has no effect there, and any cashier with
  `void_order` may remove, reduce or change sent food. The rejected alternative was:
  when the switch is ON on a paper-channel order, treat every sent line as finished
  food, so a cashier gets `finished_food_needs_manager`.
- **Audit coverage in 001A:** slice 001A ships the complete API §4.33 coverage of its
  audit writers, including the l10n titles and Dashboard registry entries, as an
  approved exception to the shared-package split (§9.2).
- **#288 coordination:** no fixed fallback date, and an information-only claim
  comment on #288 (header note rules a and c).

## 5. Current system facts the design relies on

Verified at `86a3e247`:

- **Order identity and numbering:** client-minted UUID primary key; display code =
  UUID tail; `receipt_number` assigned only inside `app.record_payment`.
- **After submit, the only changes today are:** add items (`order.items_add` →
  `app.add_order_items`, PSC-001C service rounds, round number ≥ 2); a discount
  through `app.apply_discount`; and a whole-order void (`app.void_order`, PSC-001D KDS
  acknowledgement; printer-only VOID dispatch). The shipped POS sends only
  `scope='order'` (`apps/pos/lib/src/data/discount_repository.dart`). The RPC and the
  `sync_push` `order.discount` arm also accept `scope='order_item'` with an
  `order_item_id`; that path rewrites one live line's `line_discount_minor` and
  `line_total_minor`, then re-rolls `subtotal_minor` and `grand_total_minor` from the
  live lines. It already skips voided and cancelled lines, so it needs no change for
  this design. `submit_order` also accepts a per-line `line_discount_minor`; that is
  where the "item discount" lines in §6/§8/M1/M3 come from. Apart from that
  item-scope discount, nothing in SQL, sync ops or the POS can void a single item or
  change its quantity or options; API_CONTRACT §4.2 `update_order_item` and §4.6
  `void_item` are docs-only.
- **Money:** integer minor units; line totals recomputed by the server from client
  snapshots (D-008); order discount and tax are stored as absolute amounts;
  `add_order_items` adds a subtotal delta and never adds tax. Payments are
  single-shot full payments; a live completed payment freezes the order's money
  (D-023/D-024).
- **Reports** read live lines (voided/cancelled excluded); `void_count` counts voided
  orders only; the owner reports require `subtotal = Σ live line_total`.
- **KDS:** no `kitchen_tickets` tables exist; the KDS builds tickets on the client
  from order, item, modifier and round rows pulled every **5 seconds** (no realtime
  receive path in production). Voided lines silently disappear; a work unit whose
  lines are all voided vanishes.
- **Printer-only paper:** the acting POS prints directly; the
  `kitchen_print_dispatches` ledger (`initial_order`, `service_round`, `void`) is
  drained by the POS spool only at startup, resume or context refresh. The ledger's
  key function maps any unknown dispatch type to `void:<order_id>`, and the payload
  builders do not filter item status.
- **Writes** go through `app.sync_push` (16 ops in both allowlists; 17 in the DB CHECK
  including `kiosk.order.submit`). Only `order.submit` uses the durable offline outbox;
  add items, void, discount and payment are online-only direct calls.
- **Concurrency:** every writer locks the `orders` row first; `expected_revision` is
  optional and raises 40001 on mismatch.
- **Display-order snapshots:** the MENU-ORDER-001 BEFORE INSERT triggers
  (`20260731090000_menu_order_001_reorder_and_display_snapshots.sql:72-89` and
  `:150-177`) always re-derive the item, category, group and option display-order
  snapshots from the live menu, whatever the writer supplies; only an explicit
  non-zero `order_items.line_position` is honoured.

## 6. Scope and eligibility (v1)

An order may be edited when **all** hold:

- order type `dine_in` or `takeaway`;
- status `submitted`, `accepted`, `preparing`, `ready` or `served`;
- **no live completed payment** (same predicate as `add_order_items`);
- the device is a POS, the actor is a cashier, manager, restaurant_owner or
  org_owner, and the device is **online**;
- the order's submit has been acknowledged by the server (not still in the outbox);
- the branch switch `order_edit_enabled` is ON.

Change kinds: **remove** a line, **set quantity** (up or down), **modify** a line
(modifiers and note only; "apply to all N / just 1"), **add** a line. A modify keeps
the line's size and variant: they and the base price are copied from the old row
server-side (M3). To change a size or variant, the cashier removes the line and adds
a new one, which is priced at the current menu price (M4). The POS does not offer a
size or variant picker in edit mode. Order-level fields (type, table, customer, order
note) are not edited here; table moves keep using the existing Move table action.

## 7. Behaviour

### 7.1 Cashier (POS)

1. **Entry.** An "Edit order" button next to "Add items" in `OrderActionRow`
   (`apps/pos/lib/src/widgets/order_action_row.dart`). The row is rendered by the
   Orders sheet (`recent_orders_sheet.dart`), the order detail preview
   (`order_detail_preview.dart`, which the open-orders strip opens through
   `OrderDetailPreview.show`) and the table recovery sheet
   (`table_order_recovery_sheet.dart`). The order confirmation screen
   (`order_confirmation.dart`) does not use `OrderActionRow` and has no "Add items"
   button, so it gets no "Edit order" entry in this design; the cashier reaches the
   edit from the Orders sheet, the strip or the table. If the owner wants the entry on
   the confirmation screen too, ORDER-EDIT-001E must add it there explicitly, gated by
   `actions.canEditOrder`. The label reuses the existing, already translated
   `posRecoveryEditOrder`.

   Visibility comes from a new `canEditOrder` in `resolveOrderActions`
   (`apps/pos/lib/src/data/order_actions.dart`) that copies the `canAddItems`
   interlocks (not `canVoid`): not terminal; dine-in or takeaway; not charged by the
   local marker **or** the server settlement; no pending operation; real mode; branch
   switch ON (hidden when unknown, since it is a rollout gate). It also adds the §6
   acknowledgement rule, which `canAddItems` does not have: `!submitUnacknowledged`,
   the existing `posSubmitUnacknowledged` value that the caller already passes in via
   `PosOrderActionsAssembly.submitUnacknowledgedFor`. This is needed because
   `pending == null` covers only `created`/`pending` outbox entries; a submit that is
   `in_flight`, `auth_hold`, `rejected` or `dead` would otherwise show Edit for an
   order the server may never have accepted. While the submit is unacknowledged the
   button is hidden, or blocked with "Waiting for the order to reach the server".
   `posSubmitUnacknowledged` fails open (no local submit entry, or a server snapshot
   exists, counts as acknowledged); for that case the server's `order not found`
   refusal from `pos_order_detail`/`edit_order` maps to the same message, not a
   generic error. Offline the button is blocked with "Editing needs a connection so
   the kitchen is told".
2. **Start.** The cart must be empty; instead of a dead-end message the POS offers
   "Park current cart" or "Clear". A new `OrderEditController` (pattern of
   `AdditionController`) reserves the order and fetches the extended
   `pos_order_detail`, then `CartController.loadForEdit` builds, validates and swaps
   the cart (pattern of `restoreDraft`). Each cart line is bound to its source
   `order_item_id` and keeps its original base and option prices.
3. **Edit mode.**
   - An amber banner "Editing #A1B2C3 · Table 4" with "Discard changes".
   - Each line shows its kitchen stage from its work unit: Waiting / In kitchen /
     Ready / Served; on printer-only branches every line shows "Printed".
   - Tap a line → the modifier sheet opens pre-filled (modifiers and note only, §6).
     When quantity > 1 it offers **"Apply to: all N / just 1"** ("one of the three
     burgers without tomato").
   - The stepper changes quantity; the trash icon strikes the line through with Undo;
     menu taps add lines badged "New".
   - **No-merge rule:** in edit mode a menu tap never merges into a sent line (today
     `cart_controller.dart` merges plain lines); a sent line grows only through its
     own stepper ("+1").
   - Lines whose item or option has left the menu are "keep or remove only"; lines
     with an item discount or a legacy (pre-002A, see §9.1 M1a) price are "remove
     only".
   - If the cashier's `void_order` capability is denied, remove/reduce/modify are
     disabled with an explanation; additions and "+1" quantity increases on sent lines
     remain possible. When the finished-food switch is ON on a KDS branch, Ready and
     Served lines show "Manager needed" to a cashier.
4. **Footer.** "Was ₪85.00 → Now ₪78.00 (−₪7.00)", the tax line computed with the
   same rule as the server (`apps/pos/lib/src/format/tax_math.dart`), and "Discount
   ₪10.00 kept". "Send changes" is disabled when nothing changed, when every line
   would be removed (that is a cancellation: the POS opens the existing Cancel order
   flow), when the discount would exceed the new subtotal ("Lower discount"), or when
   the new total is ₪0 and the user lacks the full-comp right.
5. **Reason.** One-tap chips, shown only when something is removed, reduced or
   modified: Customer changed mind / Order entry mistake / Item unavailable / Kitchen
   issue / Other (+ text ≤ 200). "Customer changed mind" is preselected only when
   every such change touches a ticket the kitchen has not yet acknowledged (stage
   Waiting, unit `submitted`). This is a convenience default only: the kitchen may
   already be cooking it (owner decision 3), and the reason is still recorded and
   reported. Otherwise the cashier must choose. Pure additions and increases ask for
   no reason.
6. **Finished food.** Only when a change removes, reduces or remakes a Ready or
   Served line: one confirm sheet listing those lines ("Already cooked: recorded as
   removed after kitchen") and the old → new total.
7. **Send.** A pure diff engine (`apps/pos/lib/src/data/order_edit_diff.dart`) turns
   baseline versus cart into the change list plus the expected totals. The attempt is
   frozen with a new `local_operation_id`, journaled durably **before** dispatch
   (pattern of the addition journal), and sent directly through `sync_push` as
   `order.edit`. While it is pending, Pay, Discount, Cancel, Add items, Move and Edit
   are withdrawn for that order.
8. **Result.** A toast from the server's landing summary. When
   `kitchen_ack_required` is true: "Change N sent: kitchen must confirm" (no separate
   "not started" wording, because a Waiting ticket also needs confirmation, owner
   decision 3). When the change landed only in a new ticket on a KDS branch: "Change N
   sent: new ticket for the kitchen". On paper: "Change N printed for the kitchen".
   When food is remade, add: "Already cooked: 1 dish will be remade". The POS never
   says the kitchen "hadn't started": it only knows whether the ticket was
   acknowledged. The order card shows the new total, an "Edited" chip and later
   "Kitchen confirmed". A pre-bill printed earlier is marked outdated ("Bill changed:
   print new bill?").
9. **Refusals write nothing.** `line_changed` or `totals_mismatch` (another till
   changed the order) trigger an automatic **rebase**: re-fetch, re-apply the
   cashier's intents to the fresh lines, show what changed, and resend with a new
   operation id. Other refusals have a typed message (§8.2). A transport failure
   retries the same identity; Cancel is refused until the outcome is known; the
   journal survives a restart.

### 7.2 Kitchen with a screen (KDS branches)

- **Timing:** the KDS polls every 5 s; a change appears within about 5 seconds,
  signalled visually (no audio in v1).
- **Data:** a new money-free `order_edits` entity is added to the KDS pull, plus
  non-money provenance columns on rows it already pulls (§8.1). The "was" text comes
  from the retired row, which is still pulled.
- **Confirmation rule (owner decision 3):** an edit requires a kitchen confirmation
  when it wrote to, or removed from, a work unit that was `submitted`, `accepted`,
  `preparing` or `ready` at commit — including a ticket the cook has not yet
  acknowledged. No confirmation when the edit only opened a new ticket or only
  touched served food.
- **Rendering** (a new, separate post-pass in
  `packages/feature_kitchen/lib/src/kds_ticket_mapper.dart`; grouping, FIFO, counts
  and the one-card-per-work-unit rule are unchanged):
  - the affected card gets an amber header "CHANGED · Change 2 · 12:41 · Customer
    changed mind"; live lines are badged NEW / CHANGED (was: 2× Burger +Tomato) /
    "+1"; removed lines are shown struck through in red "REMOVED 1 × Fries"; counts use
    live lines only;
  - a unit emptied by the edit shows a standalone amber card "All items of this ticket
    removed" in its former column (mirroring the PSC-001D card);
  - a ticket opened by an edit is labelled "Change 2 · Round 3" with lines tagged NEW
    or REMAKE "instead of: Burger (+Tomato)".
- **Admission:** an order with a pending confirmation stays on the board for its
  change cards even if it was paid and completed meanwhile, so a removal is never
  hidden. A **voided** order is governed only by the PSC-001D rule: a whole-order void
  supersedes every pending edit confirmation. The KDS shows the red card while
  `kitchen_ack_required` is true and `kitchen_ack_at` is null; the card includes round
  items and excludes lines with `removed_by_edit_id`. Once the void is acknowledged,
  or if no acknowledgement was required, the order leaves the board. Change cards and
  "Got it" are never rendered for a voided order. Direct-print orders stay off the
  KDS.
- **Alert:** a finite visual pulse keyed by (work unit, edit number); a second edit
  pulses again. (Today the first-seen highlight is keyed by ticket id, so an edited
  ticket would never re-alert.)
- **"Got it":** while a unit has a pending change, its advance button (and Acknowledge
  on a new ticket) is replaced by "Got it", which sends `order.edit_ack` {order_id,
  up_to_edit_number}. It covers every change up to that number, clears on every KDS
  of the branch within one poll, is idempotent, never hides a newer edit, and never
  blocks payment or status progress on the server.
- **Kitchen printers on KDS branches:** print-on-Acknowledge must print the ticket
  re-derived after the post-push pull (today it prints the ticket captured at tap
  time), so an edited, unacknowledged ticket prints fresh. When the device
  auto-prints, "Got it" prints one money-free change chit for units already printed
  (stage `accepted`..`ready` at edit); dishes that landed in a new round print on that
  round's own Acknowledge, so no dish appears on two papers.
- **Honesty:** the stage is judged per work unit (order status for the original
  ticket, round status for a round), never per dish, because item statuses do not
  advance. Labels say "In kitchen", not "cooking this burger".

### 7.3 Kitchen without a screen (printer-only branches)

- **Channel:** "paper" iff `branches.kitchen_workflow_mode = 'printer_only'` OR
  `orders.dispatch_mode = 'direct_print'`. A direct-print order on a branch that has
  since switched to KDS is refused (`kitchen_mode_changed`); a KDS order on a branch
  now printer-only goes to paper.
- **No confirmation step** on paper. Every touched line counts as stage "printed";
  removed lines become `voided`.
- **Immediate print (owner decision 4):** when the server answers `applied`, the
  acting POS prints **one** money-free change slip through the shared kitchen ticket
  builder (`packages/feature_kitchen/lib/src/print/kds_ticket_print_builder.dart`, new
  `KitchenTicketDocumentKind.orderChange`, ar/he/en with the Q-015 raster fallback):
  1. `*** ORDER CHANGED · Change N ***`
  2. the same #code, order type, table or customer, time, staff first name, reason
  3. REMOVED (thermal printers cannot strike through)
  4. CHANGE "was → now", and quantity changes
  5. ADD (new lines and "+N" quantity increases that land in the edit's round). The
     paper channel never prints REMAKE: a modified line appears only under item 4 as
     CHANGE "was → now" (§8.3, Paper column).
  6. **ORDER NOW** — every live line of the order
  7. footer "Replaces earlier tickets for #code"
- **Exactly once:** guard key `<orderId>|edit:<orderEditId>`; the print result is
  awaited (today's addition print is fire-and-forget); anything short of "sent"
  raises a persistent "Kitchen change slip not printed · Print again" banner that
  reprints the same document under the same guard. A newer edit of the same order
  retires every older pending "Print again" banner for that order, because that
  edit's dispatch is superseded and the newer slip's ORDER NOW list is authoritative.
  Before any "Print again", the POS re-reads the order's `edit_count` (edits are
  online-only, so this works); if a newer edit exists, including one made on another
  till, the old slip is not reprinted and the POS offers to print the latest edit's
  change slip instead.
- **Durable backup:** in the same transaction the server writes an `order_edit`
  dispatch (key `edit:<order_edit_id>`, money-free payload, 32 KB cap) through a new
  internal creator, leaving the pinned 10-argument `create_kitchen_dispatch`
  untouched. The dispatch is created **already claimed by the acting POS**
  (`claimed_at = now()`, `claimed_by_device_id = p_device_id`,
  `claim_expires_at = now() + 10 minutes`), using the same claim-at-submit pattern as
  KIOSK-PRINT-114B.1 (`20260825090001_kiosk_kitchen_dispatch_claim_114b2.sql:851-891`).
  Because of the lease, no other till's drain can claim it while the acting POS
  prints. `acknowledge_kitchen_print_dispatch` accepts only the claim holder, so the
  acting POS acknowledges it itself:
  - awaited direct print reports sent → `transport_accepted` (the holder may still do
    this after the lease expires, as long as no other device has claimed it);
  - any other outcome → `failed_retryable`, and the "Print again" banner shows;
  - "Print again" succeeds → `transport_accepted`.

  Only a dispatch whose lease lapses while still unresolved is printed by another
  till's drain; if a later "Print again" then gets `not_claim_owner`, the result is a
  possible duplicate slip, which is the documented residual. The dispatch supersedes
  unresolved earlier initial/round/edit dispatches of the order (ORDER NOW is
  authoritative; supersession shape in §8.1), so stale paper never prints after a
  change slip; a later VOID supersedes it. The spool imports it and consults the
  local print claim, so the acting till prints no second slip if a re-drive serves
  the dispatch back to it; it then sweeps superseded local jobs.
- **Latency:** the spool drains only at startup, app resume or explicit context
  refresh (the cadence locked by KITCHEN-MODE-001C2B;
  `apps/pos/lib/src/spool/pos_kitchen_spool_runtime.dart`); the awaited direct print
  plus "Print again" is the v1 safety net. A periodic drain is a separate follow-up
  (§13).

## 8. Server contract

All schema changes are additive and backward compatible; migrations are timestamped
after `20261006140000`; writes go only through SECURITY DEFINER functions reached via
`app.sync_push`; new public wrappers follow D-037.

### 8.1 Schema

- **`public.order_edits`** (new, money-free, append-only): id; org/restaurant/branch
  and order composite FKs (RESTRICT); `edit_number` ≥ 1, unique per order, allocated
  as max+1 under the order lock; `device_id` + `local_operation_id` unique per org;
  PIN session, employee and membership; `reason_code` in (customer_changed_mind,
  entry_mistake, item_unavailable, kitchen_issue, other) or null; `reason_text` ≤ 200;
  `kitchen_channel` in (kds, paper); `kitchen_ack_required`; the ack triple (time,
  employee, device) all-or-none, only when required, write-once; `bill_presented_at`;
  timestamps and `deleted_at`. FORCE RLS: SELECT scoped like `order_service_rounds`;
  INSERT/UPDATE/DELETE denied to clients; a trigger allows only the one-time ack
  stamp and `updated_at` to change.
- **`order_items`:** `edit_id` and `removed_by_edit_id` (composite FKs to
  `order_edits`), `replaces_order_item_id` (composite FK to `order_items`),
  `removed_kitchen_stage` in (submitted, accepted, preparing, ready, served, printed)
  — a provenance column, **not a state**. CHECKs: removed ⇒ status in (voided,
  cancelled); removed ⇔ stage recorded; replaces ⇒ edit_id. A write-once trigger
  guards the four columns. Add UNIQUE (organization_id, order_id, id) as the FK target.
  The MENU-ORDER-001 display-order triggers are **not** changed (§8.2 step 15).
- **`order_service_rounds`:** `edit_id` (round opened by an edit) and
  `voided_by_edit_id` (CHECK ⇒ status `voided`).
- **`orders`:** `edit_count` int ≥ 0, default 0.
- **`branches`:** `order_edit_enabled` (default false) and
  `order_edit_finished_food_manager_only` (default false), set by a new
  `app.set_branch_order_edit_settings` (restaurant_owner or above; idempotent; audited
  `settings.branch.order_edit_updated`; INVOKER public wrapper revoking PUBLIC and
  `anon` explicitly, D-037).
- **`kitchen_print_dispatches`:** `dispatch_type` += `order_edit`, new
  `order_edit_id` with CHECK ((type = 'order_edit') = (order_edit_id is not null)).
  **Supersession shape** (replaces the CORRECTION-001 "chain length exactly 1"
  rule): `superseded_by_dispatch_id` is write-once (NULL → value only; any later
  change RAISES 23514). The target's type must be `void` or `order_edit`, and the
  target must belong to the same org and order (existing composite FK, no-self
  CHECK). The "target is itself unsuperseded" check runs only when the pointer is
  being set (`TG_OP = 'INSERT'` or `OLD.superseded_by_dispatch_id IS NULL`); later
  status, claim or report updates on an already-superseded row are not re-checked
  (otherwise the report RPC would raise for a claimed initial row whose `order_edit`
  target was later superseded). A `void` row can never be superseded. A superseder
  points only the order's still-unsuperseded, uncompleted rows at the dispatch it just
  inserted; already-superseded rows are not re-pointed, so chains such as
  initial → edit1 → edit2 → void are allowed. Cycles stay impossible: every edge
  points from an older row to a strictly newer dispatch of the same order, created
  under the order lock, and the pointer is write-once with an unsuperseded target at
  the moment it is set. Readers only test `superseded_by_dispatch_id IS NOT NULL` and
  never walk a chain. The guard's COMMENT is updated to match.
- **`sync_operations` CHECK:** += `order.edit`, `order.edit_ack`.

### 8.2 `app.edit_order` (sync op `order.edit`)

`(p_pin_session_id, p_order_id, p_device_id, p_local_operation_id, p_payload jsonb,
p_client_created_at default null) → jsonb`; no client grant.

Payload: `{order_id, reason_code?, reason_text?, bill_presented_at?, expected:
{subtotal_minor, tax_total_minor, grand_total_minor} (required), changes[1..100]}`,
each change one of:

- `{op:'remove', order_item_id}`
- `{op:'set_quantity', order_item_id, quantity 1..999 (≠ current)}`
- `{op:'modify', order_item_id, replacements[1..20]: {quantity, notes,
  modifiers[{modifier_option_id, quantity, + full snapshot (including meat_snapshot)
  for NEW options only}]}}` — a replacement carries no item-level `prep_snapshot`;
  the server builds it (step 8).
- `{op:'add', item: the exact order.items_add item shape, line_discount_minor 0}`

Each `order_item_id` appears at most once.

**Normative: every refusal is decided before the first write.** `app.sync_push`
commits a RETURNed envelope; only a RAISE rolls back.

Validation (no writes):

1. PIN-session preamble (42501 on structural failure); device type `pos`; role
   cashier, manager, restaurant_owner or org_owner.
2. Shape: `invalid_payload`, `no_changes`, `too_many_changes`,
   `duplicate_line_reference`, `expected_totals_required`. (The authority and reason
   checks need the current line quantity, so they run in step 6a, under the lock.)
3. Business replay: an existing `order_edits` row for (org, device, operation id) on
   the same order returns the stored envelope with `idempotency_replay: true`; on
   another order RAISE 40001.
4. Locks: `orders` FOR UPDATE first (scoped; otherwise the 42501 anti-oracle), then
   its rounds, then the referenced items, then menu items, each in id order.
5. Gates: switch ON else `feature_disabled`; type dine-in/takeaway; status
   submitted..served else `order_not_editable`; no live completed payment else
   `order_already_settled`; channel resolvable else `kitchen_mode_changed`.
6. Lines: every referenced id must be a live line of this order — foreign, retired
   and missing ids all return the same `line_changed {stale_ids}`; modify or
   set_quantity on a line with an item discount → `line_has_discount`; on a legacy
   per-line-priced row (§9.1 M1a predicate) → `legacy_line_not_editable`; remove is
   always allowed.

   6a. **Authority and reason** (needs the locked line from step 6): each
   `set_quantity` is classified as an **increase** (requested quantity > the line's
   current quantity) or a **reduction** (requested < current; equal is already
   rejected by the shape rule). A `remove`, a `modify` or a reduction is a
   *removing change*; an `add` or an increase is an *adding change*.
   - Any removing change from a cashier without
     `app.cashier_capability_allowed(..., 'void_order')` →
     `permission_denied` / `removal_not_permitted`.
   - At least one removing change and `reason_code` absent (or `reason_code =
     'other'` without `reason_text`) → `reason_required`.
   - Adding changes alone need neither `void_order` nor a reason (§9.2), so a
     void-denied cashier may send an edit made only of adds and increases.
7. Finished food: on the KDS channel, a cashier removing, reducing (a `set_quantity`
   classified as a reduction in 6a) or modifying a line in a `ready` or `served` unit
   while the finished-food switch is ON → `permission_denied` /
   `finished_food_needs_manager`. On the paper channel the switch does not apply
   (§4, §9.2).
8. New lines: a new internal `app.edit_validate_new_line`, a copy of the
   `add_order_items` block (submit, add-items and kiosk are not refactored).
   - Base price, size/variant and name snapshots, and every kept option's price and
     name snapshots, are copied from the old row server-side.
   - The item-level `prep_snapshot` and every kept option's `meat_snapshot` are also
     copied (frozen quantity, unit, classifier id and name; D-008), except that each
     `classifier_selected` is re-answered by the presence of its
     `classifier_option_id` in the replacement's full `modifier_option_id` set. This is
     the same presence rule as `app.trusted_modifier_prep_snapshot` /
     `app.trusted_item_prep_snapshot`, applied to the frozen link and never to the
     live menu; without it, adding or removing a classifier option such as Cheese
     would leave the copied "with/without" answer stale.
   - The display-order snapshots (`order_items.item_display_order_snapshot` and
     `category_display_order_snapshot`; `order_item_modifiers`
     `modifier_group_display_order_snapshot` and
     `modifier_option_display_order_snapshot`) cannot be copied by the INSERT, because
     the MENU-ORDER-001 BEFORE INSERT triggers always re-derive them from the live
     menu (§5). For continuation, replacement and delta rows (not added lines), step 15
     restores them from the old row with an UPDATE after the insert. There is no
     BEFORE UPDATE guard on these columns, and the triggers are not changed, because
     `menu_order_001_test` still asserts that forged insert values are ignored.
   - New options get the 003D ownership check and the 021 prep-staleness check,
     which compares against `app.trusted_modifier_prep_snapshot(org, menu_item_id,
     option_id, <the replacement's FULL modifier array>)`.
   - `set_quantity` remainders, increase deltas and continuation rows (option set
     unchanged) copy every snapshot unchanged.
   - Every new row uses the 002A per-unit formula; sellable/available is checked
     under the lock for adds, quantity increases and a modify that raises the total
     quantity.

   Refusals: `item_unavailable`, `modifier_option_not_in_scope`,
   `modifier_prep_snapshot_stale`, `invalid_item_payload`.
9. Plan in memory: each old line's outcome (cancelled iff KDS channel and its unit is
   `submitted`, otherwise voided), the continuation/replacement/delta rows and their
   landing (§8.3), at most one new round, emptied units, `ack_required`.
10. `edit_would_empty_order` if no live line would remain.
11. Money plan (§9): `invalid_discount` / `discount_exceeds_order_total`,
    `tax_mode_unsupported`, `permission_denied` / `full_comp_permission_required` (the
    same error/detail pairs `app.apply_discount` returns, API_CONTRACT §4.5; the
    `order.edit_denied` audit records the same `denied_reason` tokens, so the existing
    POS and Activity-log mappings and l10n keys are reused), `totals_mismatch` with the
    server's figures.

Writes, in one transaction:

12. INSERT `order_edits` (number = `edit_count` + 1).
13. INSERT the edit's round if needed (round number max+1, `submitted`, `edit_id`).
14. UPDATE retired items: status, `void_reason = 'order_edit:<reason>'`,
    `removed_by_edit_id`, `removed_kitchen_stage`.
15. INSERT new items and modifiers (`edit_id`, `replaces_order_item_id`,
    `service_round_id`). Every continuation row (a reduction's remainder, an unchanged
    modify replacement) and every modify replacement carries `replaces_order_item_id`
    = the retired line; increase deltas and added lines carry none (M13 classifies on
    this). In-place rows keep the old `line_position`; a legacy old row
    with `line_position` 0 lands at max+1 through the PRINT-LAYOUT-001D trigger, which
    is accepted. In the same step, an UPDATE copies the old row's item and category
    display-order snapshots onto the new items and, matching by
    `modifier_option_id`, the old modifiers' group and option display-order snapshots
    onto the copied modifiers. New options keep the live-menu ranks that the trigger
    derived. Modifier `line_position` stays trigger-assigned (insertion order).
16. Close emptied units: a round in submitted..ready becomes `voided` with
    `voided_by_edit_id`; an emptied original unit in submitted..ready, while other
    live lines exist, moves the order to `served` **without stamping** `ready_at`: a
    unit closed from submitted/accepted/preparing keeps `ready_at` NULL, and a unit
    closed from `ready` keeps its existing write-once stamp (never cleared or changed,
    PSC-001C; `orders_ready_at_check` allows it on `served`). The jump writes no
    ready-feed occurrence. This server-side `served` closes the emptied original
    ticket. It is **not** a customer pickup and **not** a table service: the order
    still has an active round (`submitted`..`ready`) holding the edit's new or REMAKE
    lines. The jump stays, because otherwise completion could never be reached. The
    STATE_MACHINES §1 takeaway rule ("served is the customer pickup, displayed Picked
    up") is narrowed accordingly: while any service round of the order is active, the
    POS (`orderStatusLabelFor`, table recovery sheet) and the Dashboard
    (`statusLabelFor`) must not show "Picked up" or "Served"; they show the active
    round's stage ("In kitchen" / "Ready"). "Picked up" / "Served" appears only once
    no round is active. The KDS is unchanged (a served parent with an active round is
    already admitted for its round tickets only).
17. UPDATE `orders`: totals, `revision` + 1, `edit_count`.
18. Paper channel only: the `order_edit` dispatch, created claimed by the acting POS
    (§7.3).
19. Audit `order.edited` (§9.2).
20. `app.try_auto_complete_order` under the held lock.

Returns `{ok, order_id, order_code, order_edit_id, edit_number, revision,
kitchen_channel, kitchen_ack_required, new_round_id, new_round_number, unit1_closed,
rounds_closed, before{…}, totals{…}, changes[{kind, order_item_id, outcome_status,
new_order_item_ids, landing, unit_stage, remake}], kitchen_dispatch{id,
claim_expires_at} (paper channel only), server_ts, idempotency_replay}`. The
envelope is stored for replay, so a replay returns the same dispatch. `remake` is
true only for a `modify` on the KDS channel whose unit was `ready` or `served` at
commit (§8.3 "as REMAKE"); it is always false on the paper channel, where a modify
lands as CHANGE. Every RETURNed refusal is audited `order.edit_denied`.

### 8.3 Landing matrix

The unit stage is read under the lock at commit.

| Change | Unit Waiting (`submitted`, KDS) | In kitchen (`accepted`/`preparing`) | Ready/Served (KDS) | Paper channel |
|---|---|---|---|---|
| remove | line → `cancelled` | line → `voided` | line → `voided` | line → `voided` |
| reduce | old line retired; remainder written in place | same | same (nothing re-cooked) | same |
| increase | +N delta row in place | +N delta row in place | +N in the edit's round | +N in the edit's round |
| modify | old retired; replacements in place (an unchanged replacement is a continuation) | same | changed replacements in the edit's round as REMAKE | changed replacements in the edit's round as CHANGE |
| add | into the original ticket | into the edit's round | into the edit's round | into the edit's round |

On paper the edit's round gets no separate dispatch or print (the change slip covers
it) and is closed at completion by `terminalize_printer_only_rounds`, as today.

### 8.4 `app.kitchen_ack_order_edit` (sync op `order.edit_ack`)

Payload `{order_id, up_to_edit_number}`. KDS-class devices only (a POS gets
`invalid_device_type`); roles kitchen_staff, manager, restaurant_owner, org_owner;
`orders` FOR UPDATE (anti-oracle); `invalid_edit_number` when N > `edit_count`. Stamps
the ack on every pending required edit ≤ N; idempotent (nothing pending → ok with
`acknowledged_count` 0); **no write to `orders` and no revision bump**. Audits
`order.edit_acknowledged`; refusals `order.edit_ack_denied`.

Status rule: on a `voided` order it returns `order_voided` (audited
`order.edit_ack_denied`) and stamps nothing, because the void supersedes the edit and
only `kitchen_ack_void` clears it. Every other status, including `served` and
`completed`, is accepted. Readers treat a pending required edit on a voided order as
not pending: `pos_order_snapshots.kitchen_edit_ack_pending` is false, and the KDS
shows no change card.

### 8.5 Re-emitted functions (each from its live body, diffed byte-for-byte)

- `app.sync_push` (live `20261006140000`): the CHECK, both allowlists, the six
  target-bound identity lists (target id must equal `payload.order_id`; the
  fingerprint binds it) and two dispatch arms. Semantics unchanged.
- `app.order_rounds_all_served`: ignores **only** rounds with `voided_by_edit_id`.
- `app.void_order` (live `20260725090000`), with one surgical delta:
  `kitchen_ack_required` and the matching `order.voided` audit scalar become TRUE when
  the order status is `submitted..ready`, **or** any live, non-deleted service round
  of the order is `submitted..ready`, **or** an `order_edits` row of the order has
  `kitchen_ack_required` true and no ack. This covers a parent that step 16, or
  today's add-items after served, left at `served` while kitchen work is still live,
  so its live rounds never vanish without a red card. The printer-only VOID dispatch
  predicate is unchanged, because an edit always leaves an `order_edit` dispatch.
  Every other behaviour is byte-for-byte unchanged.
- `app.audit_safe_detail` / `app.audit_action_has_detail`: the new keys.
- `owner_order_history` and `owner_active_orders` item counts exclude lines with
  `removed_by_edit_id` (counts for unedited and voided orders unchanged).
- `app.pos_order_detail` is re-emitted twice (slice 2, then 001B); 001B re-emits from
  the body as left by slice 2 and diffs byte-for-byte against it.
- `app.pull_kitchen_print_dispatches` is unchanged: `order_edit` takes the existing
  ELSE rank 2. That is safe because edits are single-op online transactions and a
  VOID always supersedes an edit.
- **Precursor hardening (no behaviour change today):** `app.create_kitchen_dispatch`
  gets an explicit `void` arm and RAISES on an unknown type (today its ELSE maps any
  type to `void:<order_id>`); `kitchen_dispatch_payload_initial` and `_round` exclude
  voided and cancelled lines.

### 8.6 Read surface

- `app.sync_pull` / `app.sync_pull_changes`: entity `order_edits` with the KDS
  containment (kitchen staff on printer-only branches get nothing; the direct-print
  filter applies).
- `app.pos_order_detail` adds per item `unit_status`, a `legacy` boolean (§9.1 M1a)
  and `edit_id` (it already emits `order_item_id`, `menu_item_id`, `status` and
  `line_discount_minor`, `20260826090000_..._114b5b.sql:139-151`); per modifier
  `modifier_option_id` and the display-order snapshots (today these are used only in
  its ORDER BY); per order `dispatch_mode`, `kitchen_channel`, both switches,
  `edit_count`, `has_active_round` (bool: any `order_service_rounds` row in
  submitted..ready) and `edits[…]`. The POS parser keeps `order_item_id`,
  `menu_item_id`, status and modifier ids (it drops them today; it already reads
  `line_discount_minor`).
- `app.pos_order_snapshots` adds `edit_count`, `kitchen_edit_ack_pending` and
  `has_active_round`.
- The dashboard active-order and history reads add `has_active_round` (001G).
- `app.pin_session_capabilities` adds an advisory `void_order` boolean and
  `branch_features {order_edit_enabled, order_edit_finished_food_manager_only}` (an
  additive jsonb change; no signature change; no `set_staff_capabilities` arity
  change).
- `owner_order_edits` (new, 001G): read-only report reader, contract in API §4.47
  (§12).

## 9. Money, authorization and audit

### 9.1 Money rules

- **M1** Kept lines are untouched (rows, modifiers, snapshots, item discount, legacy
  pricing epoch; D-008).
- **M1a Legacy-price predicate.** 002A added no pricing-epoch column
  (`supabase/migrations/20260805090000_money_pricing_formula_002a_per_unit_line_total.sql:42-45`),
  so "legacy" is derived from the stored row only, never from a timestamp or a new
  column. A line L is **legacy** iff `L.line_total_minor + L.line_discount_minor <>
  L.quantity × (L.unit_price_minor_snapshot + COALESCE(Σ m.price_minor_snapshot ×
  m.quantity over L's order_item_modifiers, 0))`. A row where the two epoch formulas
  agree (quantity 1, or no priced modifiers) is not legacy and is editable, because
  the M3 recomputation reproduces its stored amount exactly. The predicate is
  computed **server-side only**: `app.edit_order` (§8.2 step 6,
  `legacy_line_not_editable`) and `app.pos_order_detail` (§8.6, the per-item `legacy`
  boolean) evaluate the same SQL expression through one internal helper (e.g.
  `app.order_item_is_legacy_priced(order_item_id)`). The POS never recomputes it and
  only reads the flag.
- **M2** Retired lines keep their row and amounts for history; their status excludes
  them from every sum.
- **M3** Continuation, replacement and delta rows copy the base price, the size/variant
  and name snapshots, the display-order snapshots (restored after the insert, §8.2
  step 15) and every kept option's price **server-side** from the old row. The item
  `prep_snapshot` and kept options' `meat_snapshot` are copied with
  `classifier_selected` re-answered against the replacement's full option set (§8.2
  step 8). Only newly chosen options carry a client snapshot, and that snapshot is
  021-validated against the replacement's full modifier array. `line_total = qty ×
  (unit + Σ mod_price × mod_qty)`, item discount 0. Lines with an item discount or a
  legacy price (M1a) can only be removed.
- **M4** Added lines follow `add_order_items` exactly (current menu price, checks).
- **M5** `subtotal_minor` is **re-rolled** as the sum of live line totals, never
  adjusted by a delta, so gross − item discount − order discount = net in reports.
- **M6** `discount_total_minor` keeps its stored absolute amount; exceeding the new
  subtotal → `invalid_discount` / `discount_exceeds_order_total` (never clamped). The
  audit records the effective discount ratio before and after.
- **M7** `tax_total_minor` is recomputed by a new `app.edit_tax_minor` from the
  branch's current tax settings on base = subtotal − discount: disabled or 0 bp → 0;
  exclusive → round-half-away(base × bp / 10000), byte-matching
  `apps/pos/lib/src/format/tax_math.dart`; `inclusive` → `tax_mode_unsupported`. The
  recompute also corrects earlier untaxed add-items lines on that order (R-008).
- **M8** grand = subtotal − discount + tax ≥ 0. **Zero-out guard:** if the total goes
  from > 0 to 0, the caller needs manager+ or `apply_full_comp`, with or without a
  discount (refusal `permission_denied` / `full_comp_permission_required`, the token
  `apply_discount` already emits) — otherwise a cashier could leave a ₪0 line and let
  the order auto-complete unpaid.
- **M9** `expected` totals are mandatory; any mismatch → `totals_mismatch` with the
  server's figures, nothing written (MONEY §1 rule 3).
- **M10** A live completed payment → `order_already_settled`. Paid orders need the
  deferred refund flow (D-023/D-024).
- **M11** Every edit bumps `orders.revision`, so a payment prepared against the old
  total (payments send `expected_revision`) gets 40001 and re-reads the new total. The
  kitchen ack never bumps revision.
- **M12** `receipt_number`, shift expected cash and the order's report bucket
  (`created_at`) are unaffected. `order_edits`, rounds and kitchen payloads carry no
  money (T-003).
- **M13** (amends MONEY §13 and the §12.2 "Money effect" line for edit-retired lines
  only; transcribed per §12). Lines retired by an edit (`removed_by_edit_id` set,
  status `voided` or `cancelled`) are excluded from Gross, Discounts and Net. They are
  also excluded from the **Voids** bucket, which stays "orders with status `voided`"
  (`void_count`, `void_total_minor`; an order voided whole after an edit still reports
  its full grand total there). They are never silently dropped: they are reported in a
  separate **Order edits** bucket for each tenant scope and business day, using the
  order's `created_at` bucket (M12):
  - `edit_count` and `edited_order_count`;
  - `removed_minor` = Σ `line_total_minor` of retired lines with no replacement row;
  - `replaced_out_minor` = Σ `line_total_minor` of retired lines that a row with
    `replaces_order_item_id` replaces;
  - `replaced_in_minor` = Σ `line_total_minor` of those live replacement or
    continuation rows (live when that edit wrote them; see below);
  - `added_minor` = Σ `line_total_minor` of live rows with `edit_id` set and no
    `replaces_order_item_id` (added lines and +N delta rows; live when that edit
    wrote them; see below);
  - `net_change_minor` = `replaced_in_minor` + `added_minor` − `removed_minor` −
    `replaced_out_minor`.

  Each figure is also broken down by `reason_code` and by employee. The gross retired
  value (`removed_minor` + `replaced_out_minor`) is always shown, so the gross void
  amounts stay visible as MONEY §12.2 requires. Net of replacements is a derived
  column and never replaces the gross figure. "Live" in `replaced_in_minor` and
  `added_minor` means live when that edit wrote them: the figures are computed per
  edit as written, from provenance only (`removed_by_edit_id`, `edit_id`,
  `replaces_order_item_id`), so a later edit or a whole-order void never rewrites an
  earlier edit's figures (ORDER-EDIT-001G; MONEY §13, API_CONTRACT §4.47).

Worked example (tax off): Burger 4000 (+Tomato, +Cucumber, both free options), Fries
1500, Cola 800 → subtotal 6300. Edit: burger without tomato, fries removed, one
lemonade 900 added → Burger 4000 (new row) + Cola 800 + Lemonade 900 = 5700.
Reports: Order edits bucket `removed_minor` 1500 (fries), `replaced_out_minor` 4000 /
`replaced_in_minor` 4000 (burger changed), `added_minor` 900 (lemonade),
`net_change_minor` −600 = 5700 − 6300, matching the audit 6300 → 5700. Voids bucket
unchanged.

### 9.2 Authorization and audit

- POS devices only; roles cashier, manager, restaurant_owner, org_owner; switch ON.
- **Additions and quantity increases** need no extra right (parity with add items);
  a `set_quantity` whose target exceeds the current quantity is classified
  server-side as an increase (§8.2 step 6a).
- **Removal, reduction or modification by a cashier** uses the existing default-ON,
  deny-only `void_order` capability (owner decision 2); the Staff screen label
  becomes "Cancel orders / remove sent items". This amends the STATE_MACHINES §2.1
  actor column for edit-originated item cancel/void on **unpaid** orders only; a
  standalone item void would stay manager+ as specified.
- **Finished food:** with the branch switch ON, only manager+ may remove, reduce or
  remake Ready/Served lines (default OFF, owner decision 2). On the paper channel
  every line is stage "printed", not Ready/Served, so the switch does not apply and
  the cashier is allowed (a §4 default, owner-confirmed 2026-10-08). The
  Dashboard says so (001G).
- **Reason** required for any remove, reduce or modify; "other" requires text.
- **Online only:** the PIN session and membership are re-validated at apply time
  (R-007).
- **Kitchen ack:** KDS-class devices; roles kitchen_staff, manager, restaurant_owner,
  org_owner (mirrors `kitchen_ack_void`).

Audit (append-only, same transaction). Classification by `app.audit_category`
(current definition: `supabase/migrations/20260725090000_kitchen_mode_001c1_dispatch_ledger.sql`):
items 1–3 fall under "orders" via the `order.%` prefix — none starts with
`order.void` or `order.discount`, so an edit never lands under voids or discounts;
item 4 falls under "orders" via the KITCHEN-MODE-001C1 `kitchen.%` rule; item 5 falls
under "settings" via the `settings.%` prefix (branch configuration work, like the
other `settings.branch.*` actions). The §4.33 classifier tests assert exactly these
categories.

1. `order.edited` — actor, device, scope, reason; old values (revision, status, edit
   count, totals, discount ratio); new values (code, edit number, change counts,
   kitchen outcome, totals, bill presented, role, device type, operation id, and
   `changes[≤100]` with per-line before/after quantities and totals, unit stage,
   landing, outcome status). This is the tamper-evident per-line record.
2. `order.edit_denied` (any refusal).
3. `order.edit_acknowledged` / `order.edit_ack_denied`.
4. `kitchen.dispatch_created` with `dispatch_type` `order_edit`.
5. `settings.branch.order_edit_updated`.

The complete API_CONTRACT §4.33 coverage ships **in the same PR as each writer**, all
in 001A: `audit_safe_detail` / `audit_action_has_detail`, pgTAP writer and
`audit_category` tests, the Dashboard `kAuditActionRegistry` entries with ar/he/en
titles, the `_displayableKeys` labels and a green `auditRegistryViolations` guard.
001A therefore also touches `packages/l10n` (keys mid-file) and `apps/dashboard`, as
an approved exception to the shared-package split, following the PSC-001D and
POS-CASH-DRAWER-MANUAL-OPEN-001 precedent. The owner approved that exception on
2026-10-08; 001C carries no audit strings.

*Implemented — ORDER-EDIT-001G (Dashboard; no shared-package or l10n change):*

- **Server.** Migration `20261009100000_order_edit_001g_owner_order_edits.sql` adds
  the read-only `owner_order_edits` reader (API_CONTRACT §4.47): M13 figures per edit
  as written, branches without a time zone left out, staff names for manager and
  above only (`staff_visible`), `reason_text` never returned. Migration
  `20261009100100_order_edit_001g_dashboard_reads.sql` re-emits `owner_active_orders`,
  `owner_order_history` and `owner_order_detail` from their live 001A bodies, adding
  only `edit_count`, `has_active_round`, `active_rounds_ready` and `edits[]`, and adds
  the reader `get_branch_order_edit_settings` (§4.47a). pgTAP:
  `order_edit_001g_owner_order_edits_test`, `order_edit_001g_dashboard_reads_test`
  and the support-session cases in `platform_support_sessions_126b_test`.
- **Overview "Order edits" card.** Shown when editing was turned on somewhere in the
  scope or the window has edits; never requested in platform support mode (the
  reader names staff). Edits, edited orders, the gross removed value always beside
  the net change, then removed, replaced (before / after) and added; by reason (an
  edit with no reason reads "Added") and by staff member when `staff_visible`; the
  newest five edits with "Load more" (25 per page, keyset). When the edits are in
  another currency than the window, or in several, it shows counts only.
- **Order lists and drawer.** A `served` order with an active round reads "In
  kitchen" on the active board, in the history and in the Overview recent orders;
  the drawer says "Ready" when every active round is ready. "Served" / "Picked up"
  return once no round is active (STATE_MACHINES §1). The "paid, not completed"
  warning waits while a round is active. "Edited ×N" sits beside the status pill.
  The drawer's "Changes" timeline lists each edit (change number, time, reason with
  the "Other" text) and what the kitchen did: waiting to confirm, confirmed at, or
  "Printed for the kitchen" on the paper channel (also shown when the change slip
  failed to print; accepted for v1). `edits[]` is parsed all or nothing, and absent
  keys from an older server read as before.
- **Settings.** An "Editing sent orders" card under Kitchen workflow holds the two
  switches over `set_branch_order_edit_settings`: owner only (managers and cashiers
  see them locked with the owner-only note), never optimistic (the server echo is
  adopted, then re-read), with the printer-only note on the finished-food switch.
  Do not turn "Allow editing sent orders" on for any branch before ORDER-EDIT-001R
  (§11).
- **Staff.** The `void_order` switch reads "Can cancel unpaid orders and remove sent
  items" with its hint; its key and its payload are unchanged.
- **Deferred until #288 merges:** the IMPLEMENTATION_CHECKLIST 001G row, the
  STATE_MACHINES §1 "Not yet implemented" note, the DECISIONS D-043 point 10
  wording, the API_CONTRACT §4.45.10 status line, and the SECURITY_AND_THREAT_MODEL
  and TESTING_STRATEGY rows.

## 10. Implementation plan

Each slice is its own Work ID, branch and PR, with pgTAP and/or Flutter tests, the
repo guards, an independent read-only review, and the owner's approval before merge.
Work IDs are proposals pending owner approval.

| # | Work ID | Scope | Depends on |
|---|---|---|---|
| 0 | **ORDER-EDIT-001** | This design note (no code) plus the §12 register transcription, merged to main after #288 merges, or earlier on the owner's explicit fallback instruction (header note, rule c), with IDs re-verified (rule b). Slice 0 is Done only when both are merged | — |
| 1 | **KITCHEN-DISPATCH-HARDEN-001** | Fail-closed `create_kitchen_dispatch`; payload builders exclude voided/cancelled lines (no behaviour change today) | 0 |
| 2 | **POS-ORDER-DETAIL-IDS-001** | `pos_order_detail` per-modifier `modifier_option_id` + display-order snapshots (re-emit from the live `20260826090000` body); POS parser keeps `order_item_id`, `menu_item_id`, item `status` and modifier ids | 0 |
| 3 | **ORDER-EDIT-001A** | DB core: schema (incl. the two `branches` columns and `app.set_branch_order_edit_settings` + its INVOKER public wrapper), `edit_order`, `kitchen_ack_order_edit`, `sync_push` re-emit, `void_order` ack-required re-emit, `order_edit` dispatch and supersession guard, `order_rounds_all_served`, item-count readers, and the audit writers **with their complete API §4.33 coverage in this same PR** (`audit_safe_detail`/`audit_action_has_detail`, pgTAP writer + `audit_category` tests, Dashboard `kAuditActionRegistry` entries with ar/he/en titles, `_displayableKeys` labels, `auditRegistryViolations` guard green) for `order.edited`, `order.edit_denied`, `order.edit_acknowledged`, `order.edit_ack_denied`, `settings.branch.order_edit_updated`; also touches `packages/l10n` and `apps/dashboard` as the approved §9.2 exception. Ships dark (switch OFF) | 1 |
| 4 | **ORDER-EDIT-001B** | Read and sync surface: `sync_pull(_changes)` entity, the remaining `pos_order_detail` fields (re-emitted from the body as left by slice 2), snapshot fields incl. `has_active_round`, capabilities projection | 2, 3 |
| 5 | **ORDER-EDIT-001C** | Shared packages (own ticket per CLAUDE.md §4): KDS mapper post-pass, change document kind and labels, spool type and decoder, pull entity, l10n keys (mid-file) for the POS, KDS and every 001G dashboard string (Order edits block, Edited ×N badge, branch toggles and the printer-only note, staff label); no audit strings (§9.2) | 4 |
| 6 | **ORDER-EDIT-001D** | KDS app: change overlay, standalone change card, "Got it", re-alert, print-on-Acknowledge re-derive, change chit, voided-order admission rule | 5 |
| 7 | **ORDER-EDIT-001E** | POS edit flow: action gate (`canEditOrder` incl. `!submitUnacknowledged`; entry point in `OrderActionRow` only — Orders sheet, detail preview / open-orders strip, table recovery sheet; confirmation screen out of scope), controller, journal, cart edit mode, split, diff engine, footer, reasons, rebase, refusals, `has_active_round` status labels | 2, 4, 5 |
| 8 | **ORDER-EDIT-001F** | POS paper: awaited change slip, claimed-dispatch acknowledgement, "Print again" with newer-edit retirement, spool import and claim consult, local supersession sweep, reprint marker | 5, 7 |
| 9 | **ORDER-EDIT-001G** | Reports, dashboard and settings: "Order edits" block via the new `owner_order_edits` reader (contract in API §4.47), "Edited ×N" badge and timeline, `has_active_round` status labels, Dashboard branch toggles over the 001A setter, staff label. On a branch with `kitchen_workflow_mode = 'printer_only'` the finished-food toggle shows "No effect without a kitchen screen: the system cannot tell when food is ready" (the value is kept, so it applies if the branch moves to KDS, Q-046). Activity Log titles are NOT here; they ship with each writer in 001A (§9.2) | 3, 5 |
| 10 | **ORDER-EDIT-001R** | Release and enablement (operations, no code) — §11 | all |

*Implemented — ORDER-EDIT-001C (shared packages; no app UI, no migration):*

- **Pull entity.** `packages/sync` `kKdsPullEntities` requests `order_edits` after the
  items, modifiers and rounds (one statement per entity, in request order). Rows are
  stored by id, so an acknowledged edit re-delivered by the next pull replaces the
  stored row. A KDS build with 001C needs the 001B migration on the server first:
  an older server refuses the unknown entity (`42501`) and the board stays in error.
- **KDS post-pass** (`packages/feature_kitchen`, `KdsTicketMapper.map(orderEdits:)`).
  A pure pass over the pulled rows, run only when edit rows exist (otherwise the
  board is byte-identical). Pending = a KDS-channel edit that requires a
  confirmation not yet given, on an order that is not voided, cancelled or
  `direct_print`; paper-channel edits are ignored. Against the last confirmed state
  it marks live lines NEW / "+N" / CHANGED "was → now" / REMAKE "instead of", lists
  REMOVED lines from the retired rows (with "Remade in Round M" when the replacement
  landed elsewhere), heads each touched card with the pending edits that touch it
  (`upToEditNumber` = the newest on that card, `alsoAcknowledges` = older pending
  numbers of the order, alert key `<ticket id>|e<N>`), and adds a standalone card
  for a touched unit that has no ticket left (an emptied round, the original unit
  after the served jump, or an order that already left the board). An order with a
  pending confirmation is admitted whatever its status, except voided. The voided
  red card skips lines with `removed_by_edit_id` and keeps round and edit-written
  lines (API §4.46). Kitchen counts and FIFO order are unchanged. The edit view model
  plucks only the money-free, identity-free fields it needs.
- **Change slip** (`orderChange`). `buildOrderChangeSlipPrintDocument` and
  `renderOrderChangeSlipBytes` print, money-free: `*** ORDER CHANGED · Change N ***`,
  the code, order type, table or customer, the edit's time, the staff first name and
  the reason; REMOVED; CHANGE as "Was:" / "Now:" lines (no arrow, because a raster
  line has one direction, Q-015) with set-quantity decreases; ADD with "+N ×" for
  increases; ORDER NOW in the server's order; the footer. Paper never prints REMAKE.
  An edit round's ticket can print "Change N · Round M" when the optional label is
  supplied (the KDS wires it in 001D).
- **Spool.** `packages/data_local` decodes the `order_edit` dispatch payload strictly
  (each `edit_lines` op reads only its own keys; an unknown op is rejected without
  echoing its value, and an unknown key is rejected by its name, never its value), and the `packages/feature_auth` pull and inspection clients
  accept the type. Until ORDER-EDIT-001F passes the slip labels, the canonical
  renderer and the legacy renderer refuse an `order_edit` job, so it is blocked
  visibly (`kitchen_render_failed`) and never misprinted as a new order.
- **l10n.** 127 keys inserted mid-file (POS, KDS, kitchen chrome, change slip, the
  five reasons, the 001G Dashboard strings); no Activity Log strings. A shared helper
  maps the reason codes (`kOrderEditReasonCodes`, `orderEditReasonLabel`).
- The API_CONTRACT §4.45.9 line that has ORDER-EDIT-001F build the spool decoder is
  superseded by this slice (design §10 row 5); that line is reconciled after #288
  merges, because API_CONTRACT is in #288's diff.

"Depends on 0" means the merged §12 register transcription, not just this note. Every
code slice (1–9) depends on it directly or through other slices.

Key tests:

- An exhaustive pgTAP matrix: every refusal writes nothing; every change kind × unit
  stage × channel lands as §8.3; money identities hold after every kind; idempotent
  replay; races serialised by the lock; completion never stalls or fires early.
- Authority: a cashier whose `void_order` is denied sends a `set_quantity` increase on
  a sent line → applied, no reason required; the same cashier sends a decrease →
  `removal_not_permitted`, nothing written.
- Legacy rows: a legacy row (qty ≥ 2 with a priced modifier, stored under the old
  formula) is refused for modify/set_quantity and allowed for remove; a qty-1 pre-002A
  row is editable.
- Display order: reorder the menu (category, item, group, option) after submit, then
  run a reduce, an increase delta and a modify continuation. The edit-written
  `order_items` and kept `order_item_modifiers` rows carry the OLD display-order
  snapshots, new options carry the live ranks, and in-place rows keep the old
  non-zero `line_position`.
- Classifier: a modify that adds or removes a classifier option while keeping the
  contributing size option stores the flipped `classifier_selected` in both the item
  `prep_snapshot` and the kept option's `meat_snapshot`.
- Takeaway closure: a takeaway order on the KDS channel at each of accepted /
  preparing / ready, where an edit empties the original unit and lands lines in the
  edit's round → status `served`, `ready_at` unchanged (NULL unless the unit was
  `ready`), round active, no auto-completion until the round is served. Flutter label
  tests: "Picked up" is not shown while `has_active_round` is true, and is shown
  after the round is served.
- Void after edit: a void after a step-16 jump to served with a live edit round raises
  the red card; a void with a pending edit confirmation supersedes it (no change
  card, `kitchen_edit_ack_pending` false, `order.edit_ack` → `order_voided`).
- Supersession: initial → edit1 → void, then a `transport_accepted` report on the
  initial row succeeds; re-pointing an already-set pointer RAISES; superseding a
  `void` RAISES.
- Two-till printer-only scenario: the non-acting till's startup/resume drain never
  prints a change slip that the acting till sent; a "Print again" for edit N after
  edit N+1 never prints N's slip.
- Property-style tests of the POS diff engine (applying diff(baseline, cart)
  reproduces the cart; totals equal the server rule); KDS mapper tests for every
  landing and closure case plus regressions (FIFO, counts, rounds, the PSC-001D card,
  direct-print ignored); print-once and drain-dedupe tests; an on-device scenario run
  in both kitchen modes.

## 11. Rollout and release

1. Deploy the migrations first. They are dark and backward compatible: old apps never
   send `order.edit` and ignore the new keys and entity.
2. Build a new KDS and a new POS (production-signed, monotonic version codes per
   [ANDROID_FLEET_UPDATE_AND_ROLLBACK.md](ANDROID_FLEET_UPDATE_AND_ROLLBACK.md)).
   Update **every KDS, then every POS** of the branch.
3. Only then turn on **"Allow editing sent orders"** for the branch in the Dashboard.
   An old KDS would silently drop removed lines and an old POS spool would reject the
   `order_edit` dispatch, so the switch is the gate and the fast rollback (APKs cannot
   be downgraded). *(ORDER-EDIT-001C: more precisely, a POS built before 001C rejects
   the whole dispatch pull page that contains an `order_edit` row, so its spool drain
   stalls until it is updated, not just that one dispatch.)*
4. Run the smoke checklist plus the edit scenarios in both kitchen modes.

## 12. Register entries to transcribe (outline; provisional IDs — header note rules a–c; merged to main before any §10 slice moves to Ready)

This section is an outline. The register text is drafted in full in ORDER-EDIT-001's
own docs PR (header note), into each owning document listed below, and is reviewed
there. Before transcription, confirm that TH-7 and every other label below is still
unused on main and in #288.

### D-043 — Sent-order edit is an in-place delta edit of the SAME open, unpaid order

- **Status:** PROPOSED (owner-approved 2026-10-08), Work ID ORDER-EDIT-001.
- **Context:** customers change orders after they reach the kitchen; the code supports
  only add-items, discounts and whole-order void.
- **Decision:**
  1. Delete-and-recreate and same-number reuse are rejected (§2).
  2. An edit changes the same `orders` row. Each edit is one append-only, money-free
     `order_edits` record numbered per order; `edit_count` and `revision` + 1.
  3. Eligibility (§6); online only via `order.edit` → `app.edit_order`; per-branch
     switch, default OFF.
  4. Change kinds remove / set_quantity / modify(replacements) / add, applied as
     close-and-insert. **No new states** (D-018 enumerations unchanged): a retired
     line becomes `cancelled` iff its work unit was still `submitted` on the KDS
     channel, otherwise `voided`; provenance columns `removed_by_edit_id`,
     `removed_kitchen_stage`, `replaces_order_item_id`.
  5. Work units: the original ticket's stage is `orders.status`, a round's its own
     status; the landing matrix (§8.3); at most one new round per edit.
  6. Unit closure: an emptied round becomes `voided` with `voided_by_edit_id`, and
     `order_rounds_all_served` ignores only such rounds (supersedes the PSC-001C
     "served only" lock for this case only). An emptied original unit moves the order
     to `served` without stamping `ready_at` (it stays NULL if the unit never reached
     `ready`; an existing write-once stamp is preserved, never cleared). This amends
     STATE_MACHINES §1.1, adding server-only `submitted`/`accepted`/`preparing →
     served` rows, and §1.2, adding a second named exception to the `submitted →
     served` prohibition, for this server-side case only. This `served` is not a
     customer pickup: while any round is active, POS and Dashboard show the round's
     stage, never "Picked up" / "Served" (§8.2 step 16).
  7. Money rules M1–M13, written out in full in the register entry and transcribed
     into MONEY_AND_TAX_SPEC (below), not by reference to this note.
  8. Authority (§9.2): additions and increases free; removals use the default-ON
     `void_order` capability (amends STATE_MACHINES §2.1 and resolves its
     §2.1-versus-§2.2 contradiction for edit-originated item cancel/void on unpaid
     orders); the finished-food switch (KDS branches only); the paper-channel policy;
     reasons. Written out in full in the register entry.
  9. Audit keys and the per-line change list (§9.2); API §4.33 coverage in 001A.
  10. Reporting (amends MONEY §13 / §12.2 for edit-retired lines only): edit-retired
      lines are excluded from Gross, Net and the Voids bucket. Voids stays
      order-level (orders with status `voided`). The lines are reported in the
      "Order edits" bucket defined in M13, which shows the gross retired value plus
      the net-of-replacement figure.
  11. Concurrency: per-line liveness plus mandatory expected totals; no
      `expected_revision` (KDS status bumps raise revision constantly).
  12. API §4.2 `update_order_item` and §4.6 `void_item` are realized for open unpaid
      orders by §4.45; no standalone item RPC is added.
- **Alternatives considered:**
  - delete-and-recreate with the same number, rejected (§2);
  - new item or order states such as `edited` or `removed`, rejected because D-018's
    enumerations are fixed;
  - standalone `update_order_item` / `void_item` RPCs, rejected (point 12);
  - `expected_revision` optimistic concurrency, rejected (point 11).
- **Consequences/risks:** R-002, R-003, R-007, R-008; threat TH-7 (test T-019).
- **Related:** STATE_MACHINES §1.1, §1.2, §2.1–§2.2, §11; API_CONTRACT §4.2, §4.6,
  §4.14, §4.15, §4.30, §4.33, §4.35, §4.45, §4.46, §4.47; MONEY_AND_TAX_SPEC §1, §6,
  §9, §12.2, §13; SECURITY_AND_THREAT_MODEL §5, §13 TH-7, §14 T-019; DOMAIN_MODEL;
  OFFLINE_SYNC_SPEC; D-008, D-013, D-018, D-020, D-021, D-022, D-023, D-024;
  Q-042..Q-046.

### D-044 — Kitchen change notification and paper

- **Status:** PROPOSED (owner-approved 2026-10-08, owner decisions 3 and 4), Work ID
  ORDER-EDIT-001.
- **Context:** today the kitchen learns of changes only through add-items rounds or a
  whole-order void.
- **Decision:**
  - KDS: `order_edits` is pulled. Changes show as an overlay on the same work-unit
    card, and an emptied unit gets a standalone change card. An order with a pending
    confirmation is admitted even when served or completed, but never when voided. A
    whole-order void supersedes pending edit confirmations; its red card is required
    whenever the order or any live round was `submitted..ready`, or an edit
    confirmation was pending, at void time (re-emitted `app.void_order`). The red card
    excludes edit-retired lines. After `kitchen_ack_void` the order leaves the board.
  - `order.edit_ack` → `app.kitchen_ack_order_edit`: KDS-class devices, up-to-N,
    idempotent, no revision bump, refused with `order_voided` on a voided order.
    Confirmation required for every change to a ticket on screen (owner decision 3).
    Visual re-alert keyed per edit (no audio).
  - Print-on-Acknowledge re-derives the ticket after the pull; the change chit covers
    only units already printed; no dish on two papers.
  - Paper channel rule and `kitchen_mode_changed`; the acting POS prints exactly once,
    awaited, with a persistent "Print again"; slip = changes + ORDER NOW (owner
    decision 4); the `order_edit` dispatch is created claimed by the acting POS and
    acknowledged by it; an older edit's reprint is retired by a newer edit.
  - `dispatch_type` `order_edit` (key `edit:<id>`, column `order_edit_id`) supersedes
    unresolved prior initial/round/edit dispatches under the write-once supersession
    shape of §8.1 (chains allowed, no cycles); VOID supersedes `order_edit`;
    `create_kitchen_dispatch` is fail-closed and the builders filter live lines.
  - Rollout rule: enable the switch only after every device of the branch is updated.
  - A periodic printer-only spool drain (changing the KITCHEN-MODE-001C2B
    startup/resume/context-refresh cadence) is out of scope; KITCHEN-SPOOL-DRAIN-002
    records its own decision under the next free D-ID when approved.
- **Alternatives considered:**
  - a full re-send or reprint of the ticket, rejected (§2 point 4);
  - no KDS confirmation, rejected by owner decision 3;
  - an audio alert, deferred to KDS-REALTIME-001.
- **Consequences:** R-002, R-007, TH-7 / T-019; version skew is gated by the branch
  switch (§11).
- **Related:** PRINTERS_AND_HARDWARE_SPEC, API_CONTRACT §4.46 and the kitchen-dispatch
  sections, ANDROID_FLEET_UPDATE_AND_ROLLBACK.

DECISIONS changelog line: "Added D-043, D-044 (ORDER-EDIT-001). The range becomes
D-001..D-029, D-031..D-044 (D-030 reserved/unratified); the next free ID is D-045+."
(Adjusted to the real range at transcription, rule b.)

### Open questions

Each row has Status **Accepted Open (D-027)**, and none blocks ORDER-EDIT-001A..G.

| ID | Question | Interacts with | Owner | Blocking scope | Leaning |
|---|---|---|---|---|---|
| Q-042 | Persisted percentage-discount basis, so an edit can re-apply a percentage | — | Human (owner) + ChatGPT | Only re-applying percentage discounts | v1 keeps the stored absolute amount (M6) |
| Q-043 | Tax-rate snapshot on orders, and `inclusive` tax for edits | Q-001 / Q-002 | Human (finance) + ChatGPT | Inclusive-tax edits and MONEY-ADD-ITEMS-TAX-001 | v1 refuses with `tax_mode_unsupported` (M7) |
| Q-044 | Inline manager approval on the same till that keeps the in-progress edit | — | Human (owner) | ORDER-EDIT-MANAGER-APPROVAL-002 | — |
| Q-045 | Editing an order whose submit is still queued offline (recall) | Q-009 / Q-010 | Human + ChatGPT | The offline-edit follow-up | v1 is online only |
| Q-046 | Switching the kitchen mode while orders are open | — | Human (owner) | KITCHEN-MODE-SWITCH-GUARD-001 | v1 refuses with `kitchen_mode_changed` |

### SECURITY_AND_THREAT_MODEL §13 — threat row TH-7

| # | Threat (STRIDE) | Description | Primary controls | Refs |
|---|-----------------|-------------|------------------|------|
| TH-7 | **T**ampering / **R**epudiation — post-send edit-down (sweethearting) | A cashier takes cash for an open unpaid order, then edits lines out or down so the recorded total is lower than what was collected | Unpaid orders only (`order_already_settled`); per-cashier `void_order` deny (`removal_not_permitted`); manager-only finished-food switch, KDS branches only (`finished_food_needs_manager`); zero-out guard (`full_comp_permission_required`, `edit_would_empty_order`); reason required for remove/reduce/modify, never preselected once the ticket was acknowledged (stage In kitchen or later); `bill_presented_at`; per-cashier and per-reason "Order edits" reporting; append-only per-line `order.edited` audit; money-free kitchen output. **Residual:** detected, not prevented, wherever cashiers may remove finished food: on KDS branches while the finished-food switch is OFF (owner decision 2), and on every printer-only branch whatever the switch says (§9.2). | D-012, D-013, D-043, R-008; Test T-019 |

### SECURITY_AND_THREAT_MODEL §14 — test T-019

- **T-019 — Sent-order edit cannot silently reduce a settled or protected order, and
  every edit is attributable.** Evaluated through `app.edit_order` (`order.edit`) with
  at least two organizations.
  - (a) A cashier carrying the explicit deny `memberships.permissions ->> 'void_order'
    = 'false'` cannot remove, reduce or modify a sent line: the result is
    `permission_denied` / `removal_not_permitted`, with no order, item, round or
    dispatch change, and the attempt is audited as `order.edit_denied`. Additions and
    increases are still allowed.
  - (b) An edit on an order with a live `completed` payment is refused with
    `order_already_settled`, with no state change, and the refusal is audited.
  - (c) On the KDS channel with the branch finished-food switch ON, a cashier cannot
    remove, reduce or modify a line in a `ready`/`served` unit
    (`finished_food_needs_manager`, audited), and a manager+ can.
  - (d) An edit that would leave no live line, or that needs a full comp the actor may
    not grant, is refused (`edit_would_empty_order` / `permission_denied` /
    `full_comp_permission_required`).
  - (e) A remove/reduce/modify without a reason is refused (`reason_required`).
  - (f) Every applied edit writes exactly one append-only `order.edited` event with
    actor, device, scope, reason and per-line before/after quantities and totals,
    under the "orders" audit category and never under voids.
  - (g) Every refusal is decided before the first write.

  *(TH-7, TH-2, D-012, D-013, D-043, RISK R-008; extends T-006)*

### SECURITY_AND_THREAT_MODEL §5 (capability table) and API_CONTRACT §4.30

- In the `void_order` row: capability label "Cancel/void an UNPAID order, or
  remove/reduce/modify its sent items"; enforcing RPCs `app.void_order` and
  `app.edit_order` (removing changes only); note that paid orders stay blocked, and
  that the per-branch `order_edit_finished_food_manager_only` switch (default OFF)
  restricts Ready/Served lines to manager+ on KDS branches.
- "The three RPCs `OR` this resolver" also names `app.edit_order`.
- API_CONTRACT §4.30 ("Enforced server-side in …"): add `app.edit_order`.

### API_CONTRACT

- **§4.45** `order.edit` / `app.edit_order` (§8.2), **§4.46** `order.edit_ack` /
  `app.kitchen_ack_order_edit` (§8.4), drafted in full.
- **§4.47** `owner_order_edits` (ORDER-EDIT-001G): read-only, `app.*` SECURITY
  DEFINER + `public.*` SECURITY INVOKER wrapper, `owner_order_history` authorization
  idiom (auth.uid → `actor_rank_in_scope`, R-003 anti-oracle), per-branch-local
  window; returns per edit and per cashier/reason the removed value net of
  replacements (M13), never in void buckets. Full contract written in 001G before
  code.
- §4.14: the real op list (17 + 2). §4.2 / §4.6: "realized for open unpaid orders by
  §4.45". §4.15: the `order_edits` entity. The `pos_order_detail` and
  kitchen-dispatch sections (incl. the supersession shape and claimed `order_edit`
  dispatch), §4.35 refusal codes and §4.33 registry rows.

### STATE_MACHINES (text only in §1.1, §1.2, §2.1–§2.2 and §11; never §12 or §13 — §13 is added by #288)

- §1.1: add server-only rows `submitted → served`, `accepted → served` and
  `preparing → served` (actor: server, only inside `app.edit_order` step 16;
  condition: the edit emptied the original work unit while other live lines remain;
  `ready_at` not stamped; audit: always, via `order.edited`; offline: No, online
  only; reversible: No). Note on the existing `ready → served` row that
  `app.edit_order` may also apply it for an emptied original unit (the write-once
  `ready_at` is preserved). No state is added (D-018).
- §1 takeaway rule: narrow "served is the customer pickup, displayed Picked up" — while
  any service round of the order is active, surfaces show the round's stage, not
  "Picked up" / "Served" (§8.2 step 16).
- §1.2: amend the `submitted → served` bullet ("ONE narrow, server-only exception")
  and the KITCHEN-PRINT-DUAL-001C / KITCHEN-DISPATCH-ENFORCE-001 note ("This is the
  ONLY legal route to that edge … it never fires on a `kds` branch") so that they name
  exactly two server-only routes, neither reachable by a client:
  `app.apply_direct_print_dispatch` (printer_only dispatch) and `app.edit_order` (an
  emptied original unit on either kitchen mode, only while other live lines remain and
  only on an unpaid order; ORDER-EDIT-001 / D-043). The direct-print route stays the
  only *dispatch* route to that edge.
- §2.1–§2.2: edit-originated item `cancelled`/`voided` on unpaid orders by a cashier
  with `void_order`, and the provenance columns. §2.1 changes the actor column; §2.2
  narrows the last Forbidden bullet to match.
- §11: rounds voided by an edit are ignored by completion; `void_order`'s
  ack-required rule covers live rounds and pending edit confirmations.
- Doc debt closed in the same commit (strictly descriptive): service rounds,
  `order.items_add`, `order.round_status` and `order.void_ack` are implemented but
  absent from STATE_MACHINES, API §4.14 and OFFLINE_SYNC_SPEC.

### MONEY_AND_TAX_SPEC (text only in §6, §9, §12.2 and §13)

- §13: add the **Order edits** bucket (definition from M13) after Voids. State that
  Voids covers voided orders and non-edit item voids, and that lines with
  `removed_by_edit_id` are reported only in Order edits. Extend the "never silently
  dropped" rule to name the Order edits bucket.
- §12.2 Money effect: edit-retired `voided`/`cancelled` lines keep their gross amounts
  visible in the Order edits bucket rather than in Voids.
- §6 / §9: an edit recomputes the whole order's tax at the branch's current rate,
  exclusive mode only (M7, Q-043). An existing absolute order discount is kept, and
  the edit is refused if that discount would exceed the new subtotal (M6), matching
  the refusal `app.apply_discount` already makes. M1–M13 written out in full.

### DOMAIN_MODEL

- New §6.4 `order_edits`: purpose, key fields, scoping, composite FKs and access, as
  in §8.1; money-free and append-only, with a one-time ack stamp. (Precedent:
  ed31543f added §4.7–§4.8 together with D-039.)
- §6.1 `orders`: add `edit_count`.
- §6.2 `order_items`: add `edit_id`, `removed_by_edit_id`, `replaces_order_item_id`
  and `removed_kitchen_stage` — provenance columns, not states, so the D-018
  enumerations are unchanged.
- §2.3 `branches`: add `order_edit_enabled` and
  `order_edit_finished_food_manager_only`.
- `kitchen_print_dispatches` (wherever the ledger is described): the `order_edit`
  type, `order_edit_id` and the supersession shape.

### OFFLINE_SYNC_SPEC

- `order.edit` and `order.edit_ack` are online-only direct ops (no outbox), alongside
  the voids row. Add the `order_edits` pull entity with its KDS containment. Done in
  the same commit that closes the existing doc debt.

### PRINTERS_AND_HARDWARE_SPEC (optional)

- One line naming the `orderChange` kitchen document kind (the spec has never carried
  the VOID slip or the dispatch ledger, which live in API_CONTRACT).

## 13. Out of scope for v1 (follow-ups under their own Work IDs)

- Editing **paid** orders (needs the deferred refund/adjustment flow, D-023/D-024).
- Offline edits and editing an order still queued in the outbox (Q-045).
- Order-level fields through Edit (type, table, customer, order note); size or variant
  changes inside a modify (remove and re-add instead, §6).
- Re-applying percentage discounts (Q-042); tax-rate snapshot and inclusive tax
  (Q-043); fixing untaxed add-items (MONEY-ADD-ITEMS-TAX-001).
- Inline manager-PIN approval on the same till (ORDER-EDIT-MANAGER-APPROVAL-002,
  Q-044); a separate "edit sent orders" capability (v1 reuses `void_order`).
- KDS realtime (sub-second) updates and audio (KDS-REALTIME-001).
- A periodic printer-only spool drain (KITCHEN-SPOOL-DRAIN-002; it changes the
  KITCHEN-MODE-001C2B spool cadence and needs its own DECISIONS entry under the next
  free ID when approved).
- Per-station routing and acks; waste capture, hold & fire, 86-from-KDS.
- Edits from the Dashboard, KDS or kiosk (only the POS edits orders).
- A guard on kitchen-mode switches while orders are open
  (KITCHEN-MODE-SWITCH-GUARD-001, Q-046).
- An "Edit order" entry on the order confirmation screen (§7.1 step 1).
- Customer-receipt annotations of edits; merging "Add items" into "Edit order".

## 14. Top risks

- **`app.sync_push` re-emit** — the hottest function; a transcription slip breaks
  every POS and KDS write. Mitigation: byte-for-byte diff against the live body, the
  source-pin suites and the full sync pgTAP run.
- **Unit closure and completion** — an emptied round, the original unit's jump to
  served, the narrowed `order_rounds_all_served`, the widened `void_order`
  ack-required rule. A mistake strands orders open, completes them early, or hides a
  live round from the kitchen. Mitigation: an exhaustive pgTAP matrix.
- **The kitchen can still miss a change** — up to 5 s behind with a visual-only alert;
  paper backup drains at startup/resume. Mitigation: confirmation on every on-screen
  change, re-alert per edit, awaited print with "Print again", the dispatch claimed by
  the acting POS.
- **Version skew** — enabling the switch before every device is updated. Mitigation:
  switch defaults OFF; the setting explains the rule.
- **Sweethearting (TH-7; test T-019)** — detected, not prevented, unless the
  finished-food switch is ON on a KDS branch; on printer-only branches it is always
  detected only (§9.2).
- **Money surprises (R-008)** — the whole-order tax recompute on tax-enabled branches;
  a percentage discount stays a shekel amount; `invalid_discount` /
  `discount_exceeds_order_total` adds friction.
- **First live writer of item `cancelled` and of voided lines on live orders** — a
  grep-based reader audit is part of 001A's review.
- **Delivery load** — about eleven PRs across the DB, sync, three packages, two apps
  and the dashboard, with register and l10n merge friction against #288. Mitigation:
  the claim comment on #288, re-verification and renumbering at transcription, and
  the owner-triggered fallback to write the registers on main (header note).
