# STOREFRONT-UI-001 Phase D1 — forward correction record

D1 is a bounded closeout of the readiness findings raised against Phase D at
commit `380b3516857126fa58891a8da56cc269bde9aae5`. It fixes four things and
corrects the record for what was claimed but not true.

**The Phase D evidence pack is sealed and is not edited.** Nothing in
`output/storefront-ui-001d-20260922T033830Z/` is rewritten, renamed or removed;
its manifest still verifies. Where a claim in it is superseded, the claim is
named here with its file and line, and the corrected figure is given alongside
the original. A reader who has the D pack in front of them should read this file
next, not instead.

Three columns are kept apart throughout, because collapsing them is how the
first record went wrong:

- **AS CLAIMED** — what the Phase D pack says.
- **BASE-REPRODUCED** — what an independent measurement of the *same* commit
  `380b3516` found. Not a D1 number: the parent's real value.
- **FINAL-MEASURED** — this build, the one D1 commits.

---

## 1. Superseded claims

### 1.1 The wide aside's stepper hit target

> `WIDE_ASIDE_PROOF.md:40` — "Its hit area is grown to 44 × 44 by an invisible
> pseudo-element, so the approved visual size is untouched"

| | value |
|---|---|
| AS CLAIMED | effective hit area 44 × 44 |
| BASE-REPRODUCED | **40 × 33** — *corrected 2026-09-22, see §5(a); this row first read 36 × 33, which was the D1 negative control, not the parent* |
| FINAL-MEASURED | **44 × 45** (AR and EN, both buttons) |

The pseudo-element existed and was 44px tall. `.asideStepper` also carried
`overflow: hidden`, which clipped it back to the painted control. The claim was
therefore true of the *rule* and false of the *result* — the pack measured the
painted box (`stepperButton { w: 36, h: 32 }`, recorded correctly at
`WIDE_ASIDE_PROOF.md:31`) and inferred the hit area from the CSS instead of
measuring it.

What changed: `overflow: hidden` is gone (nothing inside that stepper is
painted, so the clip protected nothing), and the overlay is now anchored
**outward** rather than centred, so the extra 8px falls in the row's own padding
and a tap on the quantity readout cannot change it. The painted box is
unchanged at 36 × 32 and the stepper is still 34px high — no **layout** pixel
moved. *Corrected 2026-09-22 (§5(b)):* one painted thing did change, and for
the better — with the clip gone the 3px `:focus-visible` ring on either button
is no longer cut off by the stepper box. This file originally said "no pixel
moved", which was true of geometry and not of paint.

How it is now measured rather than inferred: `tests/browser/storefront-ui-001d1.spec.ts`
walks outward from each control's centre with `elementFromPoint` and reports the
box that actually receives the press, in both writing directions. The same file
carries a negative control that re-applies `overflow: hidden` through the CSSOM
and watches the effective box collapse to 36 × 33. *Corrected 2026-09-22
(§5(a)):* that control reproduces the **mechanism** (a clip collapses the
target), not the parent's exact geometry — the parent's overlay was centred and
its clip kept 4 inner pixels, so the parent measured 40 × 33; the D1 overlay is
anchored outward, so clipping it removes all 8 and gives 36 × 33. This file
originally said "reproducing the defect exactly".

### 1.2 Both services off

> `PHASE_D_DECISIONS.md` §8 gap 4 — "Both services off | Undesigned. The CTA
> stays blocked; nothing is invented."

| | value |
|---|---|
| AS CLAIMED | the CTA stays blocked |
| BASE-REPRODUCED | `validateCheckout(draft, quote).ok === true` — **not blocked** |
| FINAL-MEASURED | `ok === false`, `blockers: ['service-unavailable']` |

This was the most consequential error in the record, because the gap entry reads
as a deliberate decision to do nothing when in fact nothing was doing it. The
draft defaults to `service: 'pickup'` before it can know the tenant;
`validateCheckout` only checked that `service` held one of two *types*, never
whether the restaurant offered it. With both services switched off a complete,
valid-looking checkout passed validation and progression was possible.

The correction is in `src/ui/storefront/checkout/validation.ts`:
`ServiceAvailability` is now a **required argument with no default**, because a
permissive default is precisely the bug. Both call sites pass the tenant's own
flags. The failure is a *blocker*, not a field error — the visitor typed nothing
wrong, and with both services off there is no answer they could give.

The negative control is the sealed parent's own code: `validation.ts` at blob
`6f5002c8531ad8f02b02c34bba0cb22669d88601` was extracted read-only into a
scratch directory and run against the identical draft and quote. It returns
`ok: true`. The D1 version returns `ok: false`; with both services *on* it still
returns `ok: true`, so the guard does not over-block; and calling it without the
argument now throws rather than guessing.

Gap 4 is closed, not carried. Gap 8 is re-stated in §1.4.

### 1.3 The wide aside and a pending quote

| | value |
|---|---|
| AS CLAIMED | the aside is live, agrees with the cart page, and its CTA goes to checkout |
| BASE-REPRODUCED | CTA was an ungated `<Link>`; **1 contradictory frame** |
| FINAL-MEASURED | `blockedWhilePending: true`; **0 contradictory frames** in 4 |

Nothing in the D pack states that the aside gates on a pending quote, so this is
an omission rather than a false claim — but the aside was the one surface that
could start a checkout against a total that had not arrived. `AsideSlot`
destructured only `{ quote }` and discarded `pending`; the immediate fixture
source made that window one microtask wide, which is why it was never seen.

A second defect was visible in the same frames: the body gate mixed "no quote"
with "no lines", so a measured frame read *"3 عناصر"* in the head and *"your
cart is empty"* in the body at the same time.

Both are corrected in `LiveCartAside.tsx`, which now distinguishes three states
— `hasLines`, `priced`, `blocked` — instead of one `ready` flag. The CTA is
three-way: a `role="status"` notice when the restaurant blocks it, an
`aria-disabled` button while a quote is pending, and a link only when there is a
settled total to order against. It is never the `disabled` attribute, so the
reason stays reachable by keyboard.

*Superseded 2026-09-22:* the button-then-link swap was itself a keyboard
regression — the focused node was destroyed on settlement and focus fell to
`<body>`. The E-stage repair keeps ONE persistent `<button>` for the pending and
settled states and navigates through the router when a matching total exists.
See `PHASE_EF_COMPLETION.md` §1.

### 1.4 First load and the remaining budget

| | AS CLAIMED | BASE-REPRODUCED | FINAL-MEASURED |
|---|---|---|---|
| flow routes, uncompressed | 670,600 | 671,605 | **672,872** |
| flow routes, Brotli | 177,217 | — | **177,863** |
| headroom to 690,000 | 19,400 | 18,395 | **17,128** |
| headroom to 200,000 Brotli | — | — | **22,137** |
| `out/` total | — | 3,935,807 | **3,937,064** |
| remaining to 4,194,304 | 258,497 | 258,497 | **257,240** |

Sources: `PHASE_D_REPORT.md:29`, `:131`, `:155`, `:159` and `D0_PROOFS.md:97`, `:105` for the
claimed column. The original figures were understated by 1,005 B; D1's own
changes cost a further 1,267 B, all of it in the shared client chunk.

Both axes still pass on all 32 routes. The flow routes remain the tightest
margin in the build, now at 97.5% of the uncompressed ceiling.

### 1.5 Capacity for Phase E

> `PHASE_D_REPORT.md:179-181` — "258,497 B remain. Phase E needs `/r/:code` in
> four locale roots. At the measured ~12.3 KB per flow document that is ~50 KB of
> documents plus the received screen's own chunk. It fits with room."
>
> Also `PHASE_D_REPORT.md:141` and `D0_PROOFS.md:100`, `:112`.

| | value |
|---|---|
| AS CLAIMED | ~12.3 KB per document; ~50 KB for E's four documents |
| FINAL-MEASURED | **35,201–35,842 B** per document; **140,802–143,368 B** for four |

The ~12.3 KB figure counted the HTML only. A static export also writes the RSC
payload a soft navigation fetches, and on this export that is **four files per
document**, not one:

```
<route>.txt                            the flat payload
<route>/__next._full.txt               the same bytes again, under the segment
<route>/__next._tree.txt               the route tree
<route>/__next.<segment>/__PAGE__.txt  the page segment alone
```

Counting only the first understates a flow route by **2.86–2.96×**. Across the
whole export, `.txt` payloads are **1,756,035 B — 44.6%** of everything shipped,
against 25.0% for HTML. The allocation this invalidates is redone in full, from
this build, in `E_F_CAPACITY_ALLOCATION.md` in the D1 evidence pack. Its verdict
is still that E fits, but with 1.4–2.0% of the 4 MiB ceiling to spare rather
than "with room", and it identifies a Phase F gate condition the original
allocation did not reach.

---

## 2. Deviation dispositions

These are the review observations D1 deliberately did **not** turn into code
changes. Each says why, and what would settle it.

| Item | Disposition |
|---|---|
| **G27 duplicate has no recovery action** (`CART_QUOTE_CHECKOUT_PROOF.md:234`) | **INTERIM — D/E boundary.** The designed recovery for a duplicate send navigates to `/r/:ref`, which Phase E owns and which does not exist yet. Offering a control that cannot go anywhere would be worse than the honest block; the banner body still says what to do. It closes when E lands, not by a change here. |
| **G27 `provenBy` in `STATE_MATRIX.json`** | **SUPERSEDED — logged locally for the owner.** The approved capture cited as proof of the failure banner was taken without the error flag set, so it evidences nothing about the banner. The four banners are asserted against `DESIGN_HANDOFF.md:130`, `STATE_MATRIX.json:238-254` and the prototype source, and captured fresh. The handoff pack is locked; this correction is recorded here for its owner and is **not** written back into it, and nothing is sent anywhere. |
| **Arrow replaced by chevron on the step CTAs** | **REVIEW-PENDING.** A visual deviation from the approved pack, raised and not resolved. It is not a correctness defect and is out of D1's bounded scope. |
| **Neither service available leaves the pickup card checked** | **REVIEW-PENDING.** With both services off nothing moves the draft, so the pickup card reads as chosen *and* announces itself unavailable. No design exists for a restaurant that accepts neither service, and inventing a cleared-selection state would be inventing product behaviour. What D1 guarantees is that it cannot be acted on. Recorded, and measured in the evidence rather than papered over. |
| **X08's narrow-aside wording** (`WIDE_ASIDE_PROOF.md:128-138`) | **NARROWED.** The original text proves the aside is in the DOM, not visible, and `display: none`. It does not establish that the aside is non-interactive, which is the property that actually matters below 900. D1 measures it: bounding box 0 × 0, 5 controls present, **0 of them focusable**, dock present. The D wording is not wrong; it was narrower than it read. |

---

## 3. What D1 did not do

Stated so a reader does not look for it: no Phase E code, no dictionary
optimisation, no redesign, no public backend, no change to `next.config.mjs`,
`vercel.json`, `package.json`, the lockfile, `tools/`, `.github/`, `supabase/`
or any governance document, and no relaxation of any budget or comparator. No
prior commit was amended, squashed or rebased. The MINOR and NOTE findings
outside the four bounded items are untouched and remain open.

---

## 4. Where the D1 evidence is

`output/storefront-ui-001d1-<stamp>/`, outside the repository, alongside the
sealed Phase D pack. It carries the closeout report, the targeted proofs, the
full E/F allocation, `MEASUREMENTS.json` with the per-document accounting for
all 32 routes, the raw gate logs, the negative-control output, the screenshots,
and a `manifest-sha256.txt` generated last.

In the repository: `tests/browser/storefront-ui-001d1.spec.ts` holds the shipped
build proofs for the hit target and the pending gate;
`tests/browser/storefront-ui-001d1-evidence.spec.ts` holds the rendered
unavailable-service proof, which needs `SF_EVIDENCE_ROUTES=1`; the availability
rules, the required-argument negative control and the wiring assertions are in
`tests/sf-flow.test.mjs`.

---

## 5. Corrections to this record made at the E/F finishing stage (2026-09-22)

The independent D1 review (`Pasted markdown(20260922-113927)`, relayed by the
owner in the FABLE FINISH LOCAL packet, §3.1) found seven inaccuracies in the
forward record. They are corrected **here and in the tracked source comments
only**. The sealed D and D1 evidence packs are not edited; where a sealed file
carries a superseded figure it is named with its line so a reader who has the
pack open knows which number is dead. Editorial corrections are not a reason to
rerun untouched runtime suites, and none were rerun for this section.

| | Was recorded | Correct statement | Where the dead figure still stands (sealed, not edited) |
|---|---|---|---|
| (a) | BASE-REPRODUCED stepper effective area **36 × 33** (§1.1 table, first version) | The parent `380b3516` measured **40 × 33** effective (centred overlay + clip keeps 4 inner px); painted 36 × 32. **36 × 33 is the D1-plus-clip negative control**, i.e. the D1 outward overlay with `overflow: hidden` re-applied through the CSSOM. FINAL-MEASURED D1 stays **44 × 45**. The D pack never hit-tested at all — it recorded the painted box and inferred the target from the rule. | `TARGETED_PROOFS.md:67-70`, `PHASE_D1_CLOSEOUT.md:66` (both correctly *labelled* "negative control"; neither claims it is the parent) |
| (b) | "no pixel moved" (§1.1) | Layout geometry unchanged (button 36 × 32, stepper 34 high — `browser-results-shipped.json`). **Focus-ring painting changed beneficially**: the 3px `:focus-visible` outline (`storefront.module.css`) was clipped by the stepper box in D and is not in D1. Painted output was never diffed; only geometry was measured. | `TARGETED_PROOFS.md:15-17, :49-50`, `PHASE_D1_CLOSEOUT.md:14, :64` |
| (c) | "45 keys / 6,621 B", labelled **DERIVED (minified size)**, explained as "186 per locale minus the 143 shipped" | 6,621 B is the byte size of a **pretty-printed SOURCE selection** (reproduces at ≈6,627 B, 2-space JSON, LF), not a minified payload (≈6,084 B) and not a count subtraction: the prototype's 186 keys and the shipped 143 are not nested — 49 prototype keys are unshipped and 6 shipped keys are ours. The actual E key set is derived from E's consumers, including dynamic state labels, with locale parity — see `PHASE_EF_COMPLETION.md` §E-KEYS. | `E_F_CAPACITY_ALLOCATION.md:104-105, :120, :223`, `PHASE_D1_CLOSEOUT.md:149-150` |
| (d) | Single-file ceiling checked on the 229,156 B largest chunk alone; the dictionaries described as "a module every route already loads" | The dictionaries live in a **separate** chunk (`0vsu0m1f8g54h.js`, 62,501 B, loaded by the 24 menu/search/flow routes, **not** by the 8 locale-root/tenant-home routes). The 262,144 B ceiling must be checked on **both** files after E. "New route, therefore no shared-chunk growth" is not a valid inference. | `E_F_CAPACITY_ALLOCATION.md:75-77, :138-142, :150, :156-158` |
| (e) | Minimum peer route family **140,804 B** (allocation row 1, low bound) | **140,802 B** (cart), as this file's §1.5 and `MEASUREMENTS.json` already say. Every low-bound total in the allocation shifts by −2 B (173,055 / 4,110,119 / 84,185; split scenario 281,604 / 313,857 / 4,250,921 / 56,617). | `E_F_CAPACITY_ALLOCATION.md:118, :122, :129, :131, :175, :199-201, :207`, `PHASE_D1_CLOSEOUT.md:122, :143-144` |
| (f) | "PG-3 forces an owner stop at Phase F regardless of E: ceiling = measured × 1.2, stop if that exceeds 4,194,304" | **Superseded.** The ×1.2 wording was written against the packet's 2 MiB ceiling; the owner re-baselined the hard ceiling to a **fixed 4,194,304 B** in `0a03485e` (`scripts/budgets.mjs`), and **no validator computes ×1.2** — the only enforcement is `audit-output.mjs` against `totalOutBytes`. The 4,724,477 / 4,963,337 figures are illustrative arithmetic, not a gate outcome. Phase F's budget check is the fixed cap plus a measured actual. | `E_F_CAPACITY_ALLOCATION.md:181-187`, `PHASE_D1_CLOSEOUT.md:133-137` |
| (g) | Three toolchain hashes (`package-lock.json`, `next.config.mjs`, `vercel.json`) printed under `| sha256 | path |` with no byte-form label | Those are sha256 of **worktree CRLF bytes** (`core.autocrlf=true`; 36,514 / 231 / 1,661 B) and cannot be reproduced from `git show`, whose **normalised LF blobs** are 35,431 / 221 / 1,607 B with different digests. The unchanged-from-parent claim holds at blob level (identical OIDs at `380b3516` and `a0260cc0`). The 13 source-file hashes are worktree bytes = blob bytes (LF). Every later pack labels each hash as **source bytes**, **normalised Git blob**, **worktree CRLF bytes** or **output bytes**. | `SOURCE_AND_EVIDENCE_BINDING.md:31-37, :39-55` |

Also corrected in tracked source: the comment above `.asideStepper` in
`src/ui/storefront/home/home.module.css` said the D review "measured" a
36 × 34 trimmed box and that a capture showed "no pixel moves"; it now states
what was inferred, what was measured (40 × 33 parent, 44 × 45 D1), and the
focus-ring change.

**What this section is not.** It is not D1 approval — the final independent
review of the whole E/F delivery is still pending — and it is not a reason to
reopen D. The D1 keyboard-focus regression the same review found is repaired in
code, not in this record; see `PHASE_EF_COMPLETION.md` §1.
