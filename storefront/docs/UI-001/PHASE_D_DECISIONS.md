# STOREFRONT-UI-001 Phase D — decision record

Cart, checkout, payment presentation, review, and the functional wide cart aside.

This file separates three things that are easy to confuse in review:

- **INHERITED** — a requirement the approved handoff, the prototype or the
  execution packet already fixed. Implementing it is not a decision.
- **DECISION** — something the pack leaves open, or gets wrong, where this build
  had to choose. Each one says what was chosen and why.
- **DEFERRED** — something that genuinely cannot be settled in this phase, with
  the marker the packet assigns it.

Line references are to the approved handoff pack
(`Mobile app design project/BIZBOT_STOREFRONT_DESIGN_HANDOFF/`) unless prefixed
`PACKET:`, which is `docs/handoffs/BIZBOT_STOREFRONT_UI_001_OPS_EXECUTION_PACKET.md`.

---

## 1. Money

### INHERITED — the arithmetic is the prototype's, verbatim

```
subtotal = sum(unit(line) x qty)
fee      = service === 'delivery' && zone && zone.fee ? zone.fee : 0
tax      = round((subtotal + fee) * TAX_RATE)
total    = subtotal + fee + tax
```
`prototype/Storefront.dc.html:692-696`. **The tax base is subtotal PLUS fee.**
That appears nowhere in the handoff prose — only in the prototype and at
PACKET:589 — so it is flagged rather than presented as locked design. Getting it
wrong under-charges tax on every delivery order; `tests/sf-flow.test.mjs` pins
both the delivery total (₪141.60) and the fact that it is NOT
`round(subtotal x 0.18)`.

### INHERITED — one authority

`src/money/quote.ts` is the only place a fee, a tax or a total is computed. The
cart, the three steps and the wide aside all render a `Quote`; none of them does
arithmetic. A source rule forbids `Math.round`, `TAX_RATE` and `taxRate` in the
aside, with a negative control that proves the rule would catch a hand-rolled
total.

### DECISION D1 — `feeMinor: 0` is free delivery; `feeMinor: null` is no delivery

The prototype tests `z.fee` for truthiness (`:694`, `:816`), so a served zone
offering **free** delivery would be reported as "we don't deliver here yet" and
would block checkout. The fixture never exercises it. `isServed()` therefore
tests `!== null`, per PACKET:554's typing, and a test covers the free-fee case
that the fixture cannot reach.

### DECISION D2 — a fee of zero is never RENDERED

Pickup, an unchosen town and an unserved town all render **no fee row at all**
rather than "₪0", because a zero would read as free delivery. Every surface
gates on `quote.feeApplies`.

The payment step's timing line is the one place the prototype breaks this: with
no zone it renders `zoneInfo{f: fmt(0)}` → "Delivery to —: **₪0** · minimum —"
(`:827`). That is not reproduced; with no served zone the line states only when
cash is paid.

### DECISION D3 — the wide aside DOES render the delivery-fee row

The prototype's aside renders subtotal / tax / total only (`:636`) while its tax
is computed on `subtotal + fee` (`:695`). At wide, Back from checkout returns to
the **menu** (`:725`) with the aside visible, so after choosing delivery the
panel reads 110 + 21.60 = 141.60 with ten shekels invisible. A totals block that
does not add up is a money defect, so the fee row is rendered on the same
`feeApplies` rule as everywhere else.

Proven in the browser: `D-X10` records `₪110 · fee ₪10 · tax ₪21.60 · ₪141.60`.

This is a deliberate departure from the prototype's markup. It changes no
approved screenshot: the canonical wide capture was taken with no zone chosen,
so the row does not appear in it either.

---

## 2. The cart screen

### INHERITED

64px thumb; 40px stepper with 44px buttons and an accent-tinted `+`; removals
prefixed `✕`; totals order; tax as a separate 18% line; the total value in
accent; a sticky footer CTA carrying the **total**; the empty state offering the
menu; the totals block AND the footer both disappearing with the last line;
one notice with one "got it"; decrementing below one removes the line with no
undo. (`DESIGN_HANDOFF.md:110-116`, `COMPONENT_INVENTORY.md:120-127`,
`INTERACTIONS.md:81-82`.)

### CORRECTION C1 — the modifier separator was wrong

Phase C joined option names with `' • '` (U+2022 BULLET). The prototype joins
with `' · '` (U+00B7 MIDDLE DOT) at `Storefront.dc.html:690` — verified
byte-for-byte as `20 B7 20` — and the approved cart screenshots render the
middle dot. Both the model and the assertion that pinned the wrong character
were corrected together.

### DECISION D4 — the notice is INJECTED, never derived

Which lines changed is a server answer that does not exist
(`OPEN_QUESTIONS.md:42-43`, marker `SNAP-001`). A screen must never invent a
reason to tell a visitor their order changed, so the three notices render from
an injected kind and the cart screen derives nothing. The demo injection lives
in `src/source/flow-scenarios.ts` — inside the fixture layer, where the source
rule requires it, and where it disappears with the fixtures.

`soldOut` reuses `changedTitle`, as the prototype does (`:849`), and the body
carries the **real** item name, not the prototype's hard-coded demo product.

### DECISION D5 — "got it" changes nothing

It hides the card. It does not remove a line, re-quote, navigate or re-enable
anything. `D-G21` asserts the stored cart is byte-identical before and after,
and that both lines are still rendered while a sold-out notice is on screen.

### DECISION D6 — the removal is announced

`INTERACTIONS.md:82` designs no feedback at all, which leaves a keyboard or
screen-reader visitor with a line that silently vanishes. PACKET:273 requires
the announcement. It is made with **authored copy only** — the `remove` label
plus the item name — because the pack has no "X was removed" sentence and
inventing one would be inventing system copy.

---

## 3. The three checkout steps

### INHERITED

The shared chrome (sticky header, back chevron, three-segment progress with the
current segment glowing, sticky footer with one CTA); the header title of step 1
saying "Checkout" while its progress label says "Details"; two 92px fulfilment
cards with pickup first in the DOM; the contact pair; the delivery block and its
zone pill with three tones and one action each; the exact shortfall measured
against the **subtotal**; the CTA that dims but stays tappable; cash
pre-selected; card a disabled radio with a dashed border and a "coming soon"
pill; the neutral timing line; the review read-back with three Edit links; the
truth notice; the ~900ms spinner; four failure banners.

Every visible validation message is an existing label — the section heading for
service, the label itself for the name, the format mask for the phone, the two
labels joined for the address pair, and no message at all for the town. The pack
contains no "this field is required" copy and none was invented.

### DECISION D7 — an unavailable service may not arrive pre-selected

The draft starts on pickup because it cannot know the tenant. A restaurant with
pickup switched off would therefore open step 1 with an impossible service
already chosen, and validation — which only checks that *some* service is set —
would let it through. The prototype forces the switch in one direction only
(`:659`, delivery→pickup); both directions are the same rule.

**This was found by a browser test, not by reading**: `D-H16` failed because the
dead pickup card was `aria-checked="true"` on `demo-closed`.

With **both** services off nothing is changed and the CTA stays blocked. No
design exists for a restaurant that accepts neither, and inventing one here
would be inventing product behaviour. Recorded as a gap, not solved.

### DECISION D8 — "switch to pickup" is withheld when pickup is off

`setService` silently refuses the switch when the target is unavailable
(`:761`), which would make the outside-zone pill's only recovery a dead end. The
action is withheld in that case and the body (`outsideZoneBody`) still tells the
visitor what to do. No new copy.

### DECISION D9 — blocked CTAs are `aria-disabled`, never `disabled`

PACKET:728. A `disabled` control leaves the tab order, taking the REASON with
it — for exactly the visitors who cannot see the dimmed fill. The two predicates
stay distinct, as the prototype has them (`:826`): `aria-disabled` is true from
the first paint, and the visual dim appears only after a blocked tap.

`disabled` is used in exactly one place: the send button while a submit is in
flight, which has nowhere to move focus to.

### DECISION D10 — a blocked tap FOCUSES, not merely scrolls

The prototype scrolls (`:724`); PACKET:285 requires focus as well. Scrolling
moves the viewport but leaves a keyboard visitor's focus on the CTA they just
pressed. `D-H14` proves the focus lands on `fullName`, then on `phone` once the
name is filled — first in DOM order, not first declared.

### DECISION D11 — the forward arrow is a chevron, not a literal "→"

`Storefront.dc.html:506` puts a literal `→` in the CTA label. In the approved
Arabic screenshot that arrow therefore points **away** from the reading
direction. The shared `ChevronIcon` is used instead and mirrors with the page.
A locked-pixel deviation, and a bug in the screenshot rather than a style
choice.

### DECISION D12 — the address joiner follows the page language

`:828` hard-codes the Arabic comma `، ` (U+060C), which is wrong punctuation in
Hebrew and English. The separator is typography, not copy, so it follows the
locale. Arabic keeps U+060C.

### DECISION D13 — entry guards

PACKET:279 and :291 require them; the prototype has neither. A static export
makes every URL directly loadable, so a visitor can land on `/payment` having
entered nothing.

- any step but the cart, with an empty cart → `/cart`
- `/payment` or `/review` with invalid details → `/checkout`

They run only after this visitor's own cart has been read — before that every
cart looks empty and the guard would bounce everyone — and they use `replace`,
so Back does not land on the page that just redirected.

### DECISION D14 — no `<form>` element

A native submit would serialise every contact field into the address bar of a
static export. There is no form, no submit button and no action.

---

## 4. Submit, and the D/E boundary

### DECISION D15 — D ends at the typed RESULT of a send

`/r/:ref` is Phase E and does not exist. An enabled control whose only outcome
is a 404 is worse than an honest block, so an accepted send hands the result to
an injected observer and this phase navigates nowhere. A test asserts that no
Phase D file builds `requestPath` or hard-codes `/r/`.

### DECISION D16 — the `duplicate` banner carries NO action in this phase

Its designed recovery is "view status", which goes to that same Phase E route.
The banner renders its title and body — "Open its status instead of sending it
again" — and withholds the action.  `COMPONENT_INVENTORY.md:149` permits at most
one action, not at least one. The key `viewStatus` is therefore **not** added:
a copy key nothing can wire is dead weight.

### DECISION D17 — one attempt at a time, and no stale completion

Nothing in the handoff or the packet addresses either; the mock hides both by
never failing slowly. The send is guarded by an attempt sequence and a liveness
flag: a completion that lands after unmount, after the route changed, or after a
newer attempt started is **discarded** — no state update, no navigation.

### DEFERRED(IDEM-001) — the idempotency key

`INTERACTIONS.md:94` requires one; `OPEN_QUESTIONS.md:46` leaves its format and
retention undefined. This build mints one opaque value per review mount, reuses
it across every retry of that attempt, derives it from nothing the visitor
typed, and keeps it in memory only — it cannot be stored beside the draft
without breaking the privacy boundary. Whether it should survive a reload is
raised, not decided.

### DEFERRED(SNAP-001) — `cart_changed`

PACKET:611 types a fifth outcome the handoff never designs and the pack carries
no copy for. It stays in the union and renders no banner. A fifth banner would
be invented copy.

### DECISION D18 — the ~900ms delay is in the gateway

`DESIGN_HANDOFF.md:130` and `INTERACTIONS.md:94` call it "product behaviour with
a mocked delay". A timer is not I/O: nothing is fetched, posted, queued, logged
or retained. Tests pass 0 so they assert behaviour rather than wall-clock.

---

## 5. Privacy

### INHERITED — memory only

`CheckoutDraft` is never written to web storage, a cookie, IndexedDB, a URL,
history state, `window.name`, a log or an analytics call, and no input handler
calls an API, a geocoder or a phone validator. The fixture gateway retains
nothing and echoes nothing back.

### DECISION D19 — the draft lives in a shared segment LAYOUT

A memory-only draft has to survive Cart → Checkout → Payment → Review, Back, and
the round trip to the menu that "add items" makes. Only a layout above those
routes stays mounted across a soft navigation, so `CheckoutDraftProvider` is
mounted at `s/[slug]`, above the flow **and** above the menu and search. It is
keyed by the canonical slug, so one tenant's draft cannot be observed by
another.

### DECISION D20 — the quote KEY carries no contact field

A quote key can end up in a cache or a log. `quoteKey` carries ids, quantities,
selections, service, zone and rate — nothing else — and a test greps it for
every synthetic marker.

Proven end to end by `D-X11`: after filling every field and sending, all nine
sinks are clean, no off-origin request is made, no request carries a marker, and
the detector is shown to work by planting one.

---

## 6. The wide aside

### INHERITED

360px at container ≥ 900px on home **and** search; title + unit count; scrollable
lines with 34px steppers; totals; a checkout CTA that goes **straight to
checkout** because the cart is already visible; no thumbnails, no kitchen note,
no Edit, no Remove, no cart notices; a one-line empty state that is not the cart
page's.

### DECISION D21 — the FRAME is always rendered; the CART never is

The dock is an overlay, so rendering nothing before hydration costs no layout.
The aside is a 360px layout **column**: returning null would reflow the page the
moment the cart is read. So the frame and the head always render and only the
lines and totals wait for `ready`.

The rule that matters does not relax. A static document is byte-identical for
every visitor, so any cart in it is a cart nobody owns — the exact defect the
Phase C review found. `tests/output/output.test.mjs` asserts the served bytes of
all eight menu/search documents carry no line, no stepper, no totals and no
money, and that all sixteen flow documents carry no cart, no prefilled input and
no money either.

### DECISION D22 — the empty count reads "0 items", not "your cart is empty"

The prototype always renders `countLabel` (`:630`), which at zero is
`items{n:0}`. Phase C's seam put `emptyCart` there instead. The prototype's
version is kept: it makes the head a constant shape, and it matches the cart
page's own header.

### DECISION D23 — the Phase B inert cart reference is DELETED

`CartParts.tsx` rendered a seeded fixture cart and was one import away from
being used — which is how that fixture reached sixteen shipped documents once
before. It is removed rather than left unused, and the boundary guard now names
the two live surfaces (`LiveCartDock.tsx`, `LiveCartAside.tsx`) and asserts no
third exists.

### DECISION D24 — the 34px stepper keeps its size and grows its HIT AREA

`COMPONENT_INVENTORY.md:183` says 34px; `DESIGN_HANDOFF.md:176` requires a 44px
minimum target. PACKET:724 (PX-6) resolves it with an invisible pseudo-element,
and PX-6 is a *proposed* deviation. The approved visual size is kept exactly and
only the hit area grows, so no pixel moves whichever way PX-6 is decided.

---

## 7. Two defects this phase found in its own work

Recorded because both were caught by a test rather than by reading, and both
would have been invisible in review.

### The quote hook was unmounting the screen

`useQuote` cleared its result whenever the inputs changed. A screen with no
quote has nothing to draw, so every quantity change unmounted and remounted the
whole cart — losing scroll position, focus, and any announcement not yet read.
It surfaced as an empty removal announcement in `D-H12`.

The hook now keeps the last matching result and reports `pending` separately. A
stale total may be **shown**; nothing may be **ordered** against it, and every
CTA gates on `pending`. The race guard is unchanged: a result whose key is not
current is still discarded on write, which `D-RACE` proves with a source that
makes a smaller cart resolve more slowly.

### `next/link` prefetch 404s on a static export

Phase D added the storefront's first `next/link`. Next's viewport prefetch asks
for a per-segment RSC payload whose path it spells with **dots**
(`__next.!KHJvb3Qp.s.$d$slug.cart.__PAGE__.txt`) while `output: 'export'` writes
the same payload as nested **directories**. Nothing serves the dotted name, so
every prefetch was a 404 — measured against the real exported tree, and true of
`/menu` just as much as of the flow.

`prefetch={false}` on every storefront link removes it. The click path is
unaffected, which `D-NAV` proves by tagging the document and showing the tag
survives two step navigations — so the soft navigation, and the draft, survive.
`D-NET` is the standing guard, with a deliberate 404 as its negative control.

---

## 8. Known gaps, carried forward

| # | Gap | Why it is not closed here |
|---|---|---|
| 1 | What raises each cart notice | `SNAP-001`; the response shape is undefined. Injected, never derived. |
| 2 | `cart_changed` has no banner | No design, no copy. Typed, unrendered. |
| 3 | Idempotency-key lifetime across a reload | `IDEM-001`; storing it would touch the privacy boundary. |
| 4 | Both services off | Undesigned. The CTA stays blocked; nothing is invented. |
| 5 | `/checkout` is not blocked while the restaurant is closed | Neither the handoff nor the prototype blocks the steps — only the dock and the aside CTA. A guard would be new product behaviour and needs owner sign-off. |
| 6 | The town `<select>` has no error message | Approved as a red border alone (`:448`). Not invented. |
| 7 | G27 does not actually show a failure banner | The approved capture was taken without the error flag set, so it proves nothing about the banner. The four banners are asserted against `DESIGN_HANDOFF.md:130`, `STATE_MATRIX.json:238-254` and the prototype source, and captured fresh here. |
| 8 | The flow routes' first load is 670,600 B against a 690,000 B ceiling | Passing, but with 19,400 B of headroom. See the report's byte section for the measured contributors and the smallest available optimisation. |

---

## 9. Where the evidence is

The browser evidence, the screenshots and the byte measurements are in the
Phase D evidence pack, outside the repository. `tests/sf-flow.test.mjs` holds
the money, validation and submit rules; `tests/browser/storefront-ui-001d.spec.ts`
the shipped-build behaviour; `tests/browser/storefront-ui-001d-evidence.spec.ts`
the states that need a demo route.
