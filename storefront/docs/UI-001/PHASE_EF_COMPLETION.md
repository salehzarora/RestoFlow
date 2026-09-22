# STOREFRONT-UI-001 — E/F completion ledger

The single storefront-local record of the finishing stage: the remaining D1
closeout, Phase E (received / status) and Phase F (integrated QA). It says what
was **inherited** from the approved sources, what was **chosen** under the
owner's finishing authorization, and what is **deferred**. It does not describe
itself as owner approval: a local implementation cannot approve itself, and the
final independent review of the whole E/F delivery is a separate step.

Line references: the approved handoff pack is
`Mobile app design project/BIZBOT_STOREFRONT_DESIGN_HANDOFF/` (`P:` = its
`prototype/Storefront.dc.html`, `DATA:` = `prototype/storefront-data.js`);
`PACKET:` = `docs/handoffs/BIZBOT_STOREFRONT_UI_001_OPS_EXECUTION_PACKET.md`;
`FINISH:` = the owner's FABLE FINISH LOCAL packet (2026-09-22).

---

## 0. Authority and precedence

**Activation.** `OWNER APPROVED — STOREFRONT-UI-001 FABLE FINISH LOCAL`
(2026-09-22), carrying the packet *BIZBOT STOREFRONT UI-001 — FABLE LOCAL
FINISHING MANDATE*. It is one bounded local authorization covering the D1
closeout, Phase E and Phase F on the existing branch
`feat/STOREFRONT-UI-001-approved-storefront`, starting from
`a0260cc0ef8faf2a022fb20311164b385e423f39`. Publication is NOT authorized:
no push, PR, merge, deployment, provider action or real backend integration.

**Precedence, recorded once.** The finishing packet supersedes only the
stage-local restrictions it names; every technical and protected invariant
remains. In particular, and so nobody resurrects them from the historical
sources this stage re-read (FINISH §2):

| Historical rule | Status now |
|---|---|
| Jira `RF-<n>` ticket before touching the tree | superseded by GOV-001 / DECISION D-038 — the approved Work ID `STOREFRONT-UI-001` |
| A new branch and PR per phase | superseded — one existing branch, ordinary local checkpoint commits |
| `out/` ceiling = measured × 1.2 (PG-3 as first written) | superseded — the ceiling is **fixed at 4,194,304 B**; no validator computes ×1.2 (see `PHASE_D1_CORRECTIONS.md` §5(f)) |
| The 1,000,000 B reserve and the 630k / 180k thresholds | Phase C readiness checks only; they do not gate E |
| Phase D's "D ends at the typed result of a send; no `/r/` navigation" (D15/D16) | ended — E supplies the destination, so the accepted send and the duplicate recovery navigate to it |
| Phase C's "neutral-only" wide aside | ended in D — functional wide cart controls; the static bytes still carry no cart |
| Full-document locale switching | **kept** — the accepted choice; served `lang`/`dir` stay correct, no client-only direction switch |
| Hero video, favicon | still out of scope; no new artwork |
| R2B | means the Security-Critical gate, not recovery automation |
| Fixture `QuoteSource` / `RequestGateway` / `StatusSource` | still fixtures in E; no real provider arrives because E starts |

The bundle the owner attached (`00_README_AR.md`, `01_FABLE_FINISH_LOCAL.txt`,
`sources/…`) was **not found on this machine** after a bounded search of the
repository, its parent, the worktrees, `Downloads`, `Documents` and the
session scratch areas. The packet text was supplied verbatim in the activation
message and is the authority used here; the D1 review's findings were taken
from the packet's own §1 and §3 quotations of it, cross-checked against the
sealed D/D1 packs on disk (`PHASE_D1_CORRECTIONS.md` §5 lists what each
correction rests on). Per FINISH §2 an unavailable historical scratch report
with an adequate supplied review is not a stop.

---

## 1. D1 closeout finished here

### 1.1 The forward record

`PHASE_D1_CORRECTIONS.md` §5 records the seven corrections the D1 review
required (40 × 33 parent target; focus-ring paint; 45 keys / 6,621 B is a
pretty-printed source selection; the dictionary chunk is not the largest
chunk; 140,802 not 140,804; ×1.2 superseded; byte-form labels on hashes). The
sealed packs are untouched: D pack 46/46 and D1 pack 25/25 manifest entries
re-verified before anything else was done.

### 1.2 DECISION E-0 — the wide aside's checkout control is ONE persistent button

**The regression.** D1 rendered `<button aria-disabled>` while the quote was
pending and swapped in a `<Link>` once it settled (`LiveCartAside.tsx`, D1
version). React unmounts the button and mounts an anchor; the focused node is
destroyed and focus falls to `<body>`. A keyboard visitor who reached the
control during the pending window lost their place the moment it became
usable. Reproduced: the negative control below records `Received: "body"`.

**The repair.** The control is a single `<button type="button">` for its whole
life — the element the prototype itself uses for this CTA (`P:636`). While
blocked it carries `aria-disabled="true"` (never `disabled`, so the reason
stays reachable), `data-sf-aside-cta="pending"`, and its activation does
nothing at all — no navigation, no focus move, no announcement. Once a
matching total exists it carries `data-sf-aside-cta="checkout"` and its
activation is `router.push(checkoutHref)`: the same soft navigation a Link
click performs (the App Router's navigate action), so the memory-only draft
survives, and with no `href` there is nothing for a viewport prefetch to 404
on. The closed/paused branch is unchanged: a `<span role="status">` stating
the reason.

**Why not restore focus after the swap.** Restoring focus needs a capture
point that runs before the old node is detached; the only reliable ones are
React commit-order details (a ref cleanup or a child layout-effect cleanup).
A control whose identity never changes needs no restoration and cannot steal
focus, which is the stronger property. The cost is that the settled control
is no longer an anchor with a visible `href`; the prototype never had one.

**What it keeps.** Pending pointer and keyboard activation inert (`E-FOCUS`
presses Enter and Space on the refusing control: URL unchanged, focus
unchanged); current-quote gating (`blocked = reason !== null || !priced ||
pending`, unchanged); soft navigation (a `data-sf-tag` set on the document
before activation is still there on `/checkout`); privacy (nothing new is
read or stored). The hidden narrow aside (< 900) still exposes no focusable
control and no landmark (`display: none`; 0 focusable of its controls).

**Proof.** `tests/browser/storefront-ui-001e.spec.ts` `E-FOCUS` — Home and
Search with the delayed `quote-race` fixture: focus survives settlement,
activation is valid only after readiness, the settlement never steals focus
that moved to the search field. **Negative control:** the same tests run
against a scratch copy of the tree carrying the PARENT's `LiveCartAside.tsx`
(blob `a0260cc0:storefront/src/ui/storefront/cart/LiveCartAside.tsx`) fail on
both surfaces with `Expected: "checkout" / Received: "body"`; the two
non-regression tests pass on both, so the control discriminates. The accepted
checkout was never modified for it. Log:
`logs/negative-control-focus-parent-aside.log` in the E/F evidence pack.

Tests that pinned the old shape were repaired with it: `sf-home.test.mjs`
(`router.push(checkoutHref)` instead of `href={checkoutHref}`) and
`storefront-ui-001c.spec.ts` C2-C (destination proven by activation, not by
reading an href).

**Measured cost** (shipped build, before → after the repair): `out/`
3,937,064 → **3,937,107 B** (+43); flow first load 672,872 → **672,839 B**
raw (−33), 177,863 → **177,884 B** Brotli (+21); the dictionary-bearing chunk
62,501 → 62,468 B (now `3keao30lrsvoc.js`); largest file unchanged at
229,156 B.

---

## 2. Phase F allocation, made BEFORE Phase E feature work (FINISH §3.3)

All figures are **output bytes** of the shipped build at the end of §1
(`SF_EVIDENCE_ROUTES` unset, Node v24.21.0), measured with the D1 attribution
method (every `out/` file belongs to exactly one canonical route or to the
shared remainder; a route owns `<route>.html`, `<route>.txt` and every
`__next.*` artefact directly under its directory). Raw data:
`MEASUREMENTS.json` in the E/F pack (`cp1-after-aside-repair`).

### 2.1 Baseline

| | bytes |
|---|---:|
| `out/` (200 files) | **3,937,107** |
| remaining to 4,194,304 | **257,197** |
| worst direct-load JS (16 flow routes) | 672,839 raw / 177,884 Brotli |
| first-load margins | 17,161 raw / 22,116 Brotli |
| largest emitted file (`25u4ugc163b9o.js`) | 229,156 (32,988 headroom to 262,144) |
| dictionary-bearing chunk (`3keao30lrsvoc.js`) | 62,468 |
| CSS (2 files) / fonts (3 files) | 73,922 / 77,164 |

### 2.2 Phase E increment (estimate, by named line)

| # | increment | low | high | basis |
|---|---|---:|---:|---|
| 1 | one canonical opaque fixture ref × four locale roots: 4 HTML + **all** emitted RSC payloads (4 files per document) | 140,802 | 143,368 | MEASURED ANALOGY — the cart (min) and review (max) families, same skeleton architecture (neutral document, everything after mount) |
| 2 | E's page chunk (received + status + cancel sheet + timeline + TTL + composer + copy) | 17,216 | 34,000 | MEASURED band 8,608–15,393 B per screen × 2, top of band raised because four mechanisms have no analogue in the tree |
| 3 | dictionary growth in the shared chunk — the actual E key set from its consumers, ≈46 keys × 3 locales | 5,500 | 6,600 | measured: the 45-key prototype selection minifies to ≈6,084 B; one execution-clarification key added |
| 4 | E's CSS module | 9,000 | 18,300 | ESTIMATED: half to all of `flow.module.css` source × the 0.734 emit ratio (lowest confidence line) |
| 5 | the in-memory handoff provider mounted in the four root layouts: one small client chunk + a client reference in every document's RSC payload | 1,500 | 7,000 | ESTIMATED: ≈1 KB chunk; ≈150 B × 36 documents |
| 6 | source-rule / test files | 0 | 0 | tests ship no bytes |
| | **total E increment** | **174,018** | **209,268** | |

Post-E projection: `out/` **4,111,125 – 4,146,375 B**; remaining
**47,929 – 83,179 B** (1.1 – 2.0%). This is an estimate, not verified
capacity; FINISH §7 requires a measurement after the minimal E scaffold and
before polish, and that measurement is recorded in §2.4.

### 2.3 Phase F reserve — explicit, nonzero, with its basis

The remainder is NOT free margin. F is expected to ship bytes for a small
named list of corrections; each is priced from a measured comparable:

| F item | expected output cost | comparable / basis |
|---|---:|---|
| keyboard-focus repair (§1.2) | **+43 B, already spent** | measured above |
| arrow-vs-chevron: a minimal exact icon restoration if the locked source is clear (FINISH §6) | ≤ 300 B | an icon path in `icons.tsx` is 100–250 B; no new component |
| bounded route / keyboard / contrast refinements found by the F pass (budgeted three) | ≈ 1,300 B each → 3,900 B | D1's own four bounded corrections cost 1,257 B of `out/` and 1,267 B of shared-chunk first load |
| the demo-only status notice (one new key × 3 locales, rendered after mount) | ≈ 300 B | key bytes only; no RSC growth |
| test-only F changes (cross-engine spec, lab protocol, coverage map) | 0 B | tests ship no bytes |
| uncertainty on the above (the F pass has not run) | ×1.6 | round the named list up, not down |
| **F reserve** | **8,000 B** | named list 4,543 B × 1.6 ≈ 7,300, rounded up |

Credibility check: post-E remaining 47,929 – 83,179 B minus the 8,000 B F
reserve leaves **39,929 – 75,179 B**, so the finish fits at every bound of
the estimate. The number was not chosen to print PASS: it is the measured
comparables scaled up, and it stays fixed through F — if F needs more, the
overrun is reported as such.

**The narrow first-load margin, separately.** The 690,000 B raw ceiling on
the flow routes has 17,161 B of headroom. E adds ≈6.1 KB of dictionary to the
shared chunk and ≈1–1.5 KB for the handoff provider → ≈9,500 B left; three
F corrections at ≈1.3 KB → ≈5,600 B left. Brotli: 22,116 − ≈1,500 − ≈500 →
≈20,000 B left. It fits; it is the tightest number in the build and it is
re-measured at every checkpoint. If it stops fitting, the permitted local
optimization is per-locale dictionary partitioning behind the existing i18n
contract (FINISH §8), estimated at 12–13 KB of first-load relief per flow
route and taken only if the final measurement needs it.

### 2.4 Measurement after the minimal E scaffold (FINISH §7)

**The estimate was wrong, and the measurement caught it before polish.** The
first E scaffold — four `r/[ref]` pages, the runtime, the fixture, the 43
dictionary keys and the handoff provider in the root layouts — built to
**4,267,380 B**: **73,076 B over the ceiling**, an increment of 330,273 B
against an estimate of 174,018–209,268.

Where the estimate failed (all output bytes, measured by diffing the two
builds document by document):

| growth | bytes | why the allocation missed it |
|---|---:|---|
| menu documents (4) | +47,144 | the home page passed the WHOLE dictionary `m` across the server→client boundary to five client components; the flight protocol serialises it into the HTML's inline payload and into three of the four RSC files of every document — so **each new key cost ~5 copies per home/search document**, not one copy in a chunk |
| search documents (4) | +46,020 | same |
| tenant-home / locale-root documents (8) | +10,804 | the handoff provider's client reference in every document (4 files each) plus the same dictionary effect on the intro |
| flow documents (16) | +36,080 | the provider's client reference and the enlarged module map, ~2.2 KB per document |
| request family (4 new documents) | +134,181 | within the 140,802–143,368 analogy (slightly under: a lighter skeleton) |
| shared: E page chunk, request CSS (+18,507), provider chunk | +56,044 | chunk ≈ 24 KB, CSS at the top of its range |

The D1 allocation priced "dictionary growth" at 6,621 B in one shared chunk.
The true marginal cost of a dictionary key in this export was **~2.5 KB**,
because the home and search pages duplicated the dictionary into their
payloads — a pre-existing cost the allocation never modelled, and the reason
"186 − 143 = needed keys" was the wrong question (PHASE_D1_CORRECTIONS.md §5(c)).

**Permitted local optimisation applied (FINISH §8, "avoiding duplicate
serialisation")** — DECISION E-OPT-1 in §3.7: the five client boundaries that
took `m` now take `locale` and resolve the dictionary from the client bundle
they already carry. Recovered **266,088 B** (menu family 1,468,547 →
1,335,195; search 437,251 → 304,331), i.e. the home/search documents are now
**smaller than before E** (1,421,403 / 391,231 at D1). No key, state or locale
was lost: every E consumer's key is asserted present in all three dictionaries
with identical placeholders (`tests/sf-request.test.mjs`), the full shipped
and evidence browser matrices pass, and the CSP and import rules are untouched.

A second route-scoped-import correction (DECISION E-OPT-2) keeps the flow
routes' first load from carrying the status fixture: the demo ref and the
`?fx=` switch live in two small modules the flow can import alone.

**Measured after E (shipped build, Node v24.21.0), the figures F starts from:**

| | bytes | vs. §2.1 baseline |
|---|---:|---:|
| `out/` (223 files) | **4,001,776** | +64,669 |
| remaining to 4,194,304 | **192,528** | |
| request family, 4 documents (HTML 46,244 + RSC 87,521) | 133,765 | new; 32,514–36,218 per document |
| worst direct-load JS: the 16 flow routes | **684,661 raw / 181,832 Brotli** | +11,822 / +3,948 |
| first-load margins | **5,339 raw / 18,168 Brotli** | |
| request route first load | 656,321 / 175,112 | new |
| largest file (`25u4ugc163b9o.js`) | 229,156 | unchanged |
| dictionary-bearing chunk (`1j9_jodcjx2he.js`) | 40,982 | re-chunked; both files checked against 262,144 |
| CSS (2 files) | 92,771 | +18,849 (the request module) |

The F reserve of 8,000 B (§2.3) stands: **184,528 B** remain above it. The
first-load raw margin on the flow routes, **5,339 B**, is the one number that
could bind in F: three ~1.3 KB corrections fit, a fourth would not, and the
per-locale dictionary lever (FINISH §8) is the documented recourse.

---

## 3. Phase E decisions

### 3.1 INHERITED — the screens, the states, the copy

The received hero, summary card, WhatsApp CTA, track button, fallback block and
message preview (`P:513-:544`); the status header, hero card, vertical
timeline, action column, order summary and cancel sheet (`P:546-:576`); the
nine states, their tones, their action sets, the pending predicate
`received || waiting` and the TTL-while-waiting rule (`P:835-:847`); the 1.6 s
copied feedback (`P:733`); the `M:SS` countdown; every string, taken
programmatically from the approved table (`storefront-data.js` export `T`),
never retyped. `STATE_TABLE` in `status.ts` is the one table; a unit test pins
it to the prototype.

### 3.2 DECISION E-1 — one opaque demo ref, one document, two views

`/r/DEMO-7K4XM2D9P3` is the only request document, in four locale roots; the
received and status screens are STATES of it, decided after hydration. The
segment is opaque and says "DEMO" in the URL; `#MB-2487` is the display code
(PD-11), resolved on the client — it is request data and does not appear in
the served bytes (`tests/output/output.test.mjs` asserts it). One authority
(`src/source/request-ref.ts`, re-exported by `request-fixture.ts`) feeds the
static params, the gateway's accepted and duplicate results, and the status
source. The Phase D order-shape hash is gone: it named a document that was
never emitted. This is a fixture allocation, not ID generation and not an
idempotency claim. Evidence scenarios add zero artefacts: every state is a
`?fx=` token on the same document.

### 3.3 DECISION E-2 — the handoff is memory in the root layout

The accepted send records the NONCONTACT summary (ids, quantities, selections,
quoted amounts, service, zone, the instant) in `RequestHandoffProvider`,
mounted in each root layout — the only ancestor that survives the soft
navigation from `/s/:slug/review` to `/r/:ref`. The type has no slot for a
contact field, a source rule greps the request side for every contact
identifier, and the flow's handoff builder is asserted to read only the quote
and the cart lines. Received is shown once ("seen"); "track status",
"continue on WhatsApp" and any later visit render status. A reload drops it:
the same URL is then the status view fed by the source, never the received
view (E-FLOW, D-X11).

**The cart is not cleared by a send** — the prototype keeps it (`P:728`) and
"order again" is the ONE designed clear (`P:737`, INTERACTIONS.md:115), so
`CartApi.clear()` exists for that action alone. A failure, a duplicate or a
stale completion changes nothing. The memory-only draft is destroyed by the
segment change itself, which is the privacy contract working as designed.

### 3.4 DECISION E-3 — the duplicate recovery and submission-time validation

The duplicate banner carries its designed one action, "view status"
(`P:831-:833`), which opens the status view — offered, never automatic. The
send now re-checks the runtime's live answer (non-empty cart, details valid for
the services the restaurant offers) AT submission, not only at route entry;
the review CTA is `aria-disabled` while that answer is no.

### 3.5 DECISION E-4 — the status source contract

`StatusSource.subscribe(ref, onSnapshot, onMissing)` never answers
synchronously; `cancel(ref, seenVersion)` is guarded by the SOURCE's state:
answered-first → `not_pending` with the newer snapshot, never a cancelled one;
a stale version is refused. The runtime accepts a snapshot only if it
`supersedes` the current one (same ref, higher version), ignores callbacks
after unmount, and clears its subscription and timers. Times on the timeline
come only from recorded events (`DEMO_AGE_MS` / `EVENT_OFFSETS_MS` are
explicit fixture records; the prototype's `createdAt + n × 4 min` is not
reproduced — PX-10). Expiry is a source event at `expiresAt`; the UI shows
0:00 until the source says expired. The fixture source is created per mount
with the visitor's seed; no module holds one visitor's request.

### 3.6 DECISION E-5 — WhatsApp is simulated, copy is real, the message is safe

`demoLauncher` returns `'simulated'` and opens nothing (DEFERRED WA-001); no
`wa.me`, `whatsapp://`, `api.whatsapp.com` or `window.open` exists in
`src/` (source rule + output test). Because the screen therefore cannot say
WhatsApp opened, one localized notice states the fact — **"Local demo — no
order or message is sent."** — an execution clarification (FINISH 4.4), the
only authored copy in E, marked as such in the dictionaries' comment. The
prototype's `href="#"` "open WhatsApp Web" is the same simulated launch.

The message is composed in the restaurant's language (Arabic, the fixture
tenant's) from the prototype's own fragments (`P:768`) with two recorded
departures: the delivery line names the ZONE only — street and building are
dedicated CheckoutDraft fields and may not reach message text (FINISH 4.2/4.4)
— and the status link is the configured origin + `/r/<ref>` (PX-2), never
`bizbot.app`. `PUBLIC_ORIGIN` is configuration
(`src/routes/origin.ts`, the approved future host); it makes no domain exist.

Copy writes the composed message only, from the one file allowed to touch the
clipboard (`clipboard.ts`; write only, no `readText` anywhere), and "Copied"
appears only after the browser reports success — the prototype flipped the
label even on failure (`P:733`). The 30 px control keeps its painted size
and reaches 44 px through an invisible overlay (PX-6).

### 3.7 DECISION E-OPT-1 / E-OPT-2 — the two permitted optimisations (§2.4)

E-OPT-1: five client boundaries (`StorefrontRuntime`, `HomeChrome`,
`SearchScreen`, `DockSlot`, `AsideSlot`) take `locale` instead of `m`.
Before/after: `out/` 4,267,380 → 4,001,292; menu documents 373,029 →
336,790 (max); search 114,960 → 78,829; no first-load change. E-OPT-2:
`request-ref.ts` and `request-scenarios.ts` are the small modules the flow
imports; flow first load 687,245 → 684,661 raw. Neither adds a dependency,
touches the CSP, the config hash, the comparator or any ceiling.

### 3.8 DECISION E-6 — accessibility and truth details the prototype lacks

- The ticking TTL is `role="timer" aria-live="off"` OUTSIDE the
  `role="status"` live region that announces state changes (PX-5c).
- The timeline is an `<ol>` with `aria-current="step"` on the current node.
- The cancel sheet is `role="dialog" aria-modal`: focus moves to "keep", Tab
  cycles inside, Escape and the scrim keep the request, focus returns to the
  cancel control; the sheet closes itself if the source moves on while open.
- Under reduced motion the request module also collapses animation DELAYS:
  the root rule collapses durations only, so the staggered "not confirmed yet"
  line would otherwise sit invisible for 350 ms under the very setting that
  promises one frame. Proven with a two-frame probe and its negative control.
- "Yes, cancel" uses the derived danger ink (`--onBad`), the danger card the
  AA-walked `--badText` (PX-3a/b); every tone pair is asserted at AA in both
  presets.
- A ref the source does not know renders the neutral unknown copy inside the
  tenant frame (`?fx=status-missing`); an ungenerated ref is a real 404.

### E-KEYS — the dictionary keys E consumes

43 keys were added to all three dictionaries, in the same order, derived from
the consumers (`ReceivedScreen`, `StatusScreen`, `requestParts`,
`RequestRuntime`, the review banner) and cross-checked by a unit test that
reads `m.<key>` from those files and asserts each exists in ar/en/he with
identical placeholders: received, receivedBody, continueWa, trackStatus,
waFallback, waWeb, copyMsg, copied, msgPreview, waiting, waitingBody,
expiresIn, accepted, acceptedBody, preparing, preparingBody, readyPickup,
readyPickupBody, readyDelivery, readyDeliveryBody, completed, completedBody,
rejected, rejectedBody, expired, expiredBody, cancelled, cancelledBody,
cancelRequest, cancelTitle, cancelBody, keep, yesCancel, openChat, orderAgain,
stReceived, stWaiting, stAccepted, stPreparing, stReady, stCompleted,
viewStatus — all verbatim from the approved table — plus **demoNotice**, the
one authored string. Not added because no consumer exists: `requestCode`,
`backToMenu`, `readyStep` (unused in the prototype too).

---

## 4. Carried forward from earlier phases (FINISH §6)

Dual popular-badge placement; safe bidi isolation and its exemptions; the
CSSOM theme transition; the honest static empty state; container-driven
asides and no phone Search dock; the middle-dot modifier separator and the
noun-form required groups; the delivery-fee row from the common Quote; no
legal tax-default assertion; the G27 original capture retained immutable and
cited only as source, with a freshly triggered failure capture as the
evidence; the D1 selected-unavailable observation (truthful unavailable /
blocked behaviour, no forced loss of cart or draft, not reopened for an
`aria-checked` attribute).

---

## 5. Non-blocking ledger

_Minor editorial observations that need no further phase._
