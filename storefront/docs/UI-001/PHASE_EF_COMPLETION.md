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

**Corrected in F (review finding).** The duplicate handoff carried
`createdAt: Date.now()` at the click, so the status view of a request the
banner had just called "already sent" showed "received <click time>" and a
fresh 29:59. A duplicate recovery did not send anything from this document:
its handoff now carries `createdAt: null`, and the fixture source ages the
request exactly as a direct load does (`DEMO_AGE_MS`), which is what the
prototype's `goStatus` shows (`P:723`, `P:648`). The summary is still the
visitor's own lines. Unit test: "a seed without a send instant … is aged like
a direct load, never stamped at the click".

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

**Corrected in F (review finding).** The reasoning above held for the aged
direct load only. For the visitor's OWN send the seed's `createdAt` is the
send instant, and `createdAt + EVENT_OFFSETS_MS` then stamped records that
had not happened yet: "waiting" at +20 s while the wall clock still read the
send minute, and with a `status-<state>` token carried from the review URL,
five stamps up to +32 min in the future — invented time, exactly what PX-10
forbids. `eventsFor` now holds every record at the clock
(`Math.min(createdAt + offset, now)`); a direct load is unaffected (all its
records are past by construction). The runtime's `supersedes` guard also
moved from a render-synchronised ref to a functional `setSnapshot`, so two
answers delivered in one task cannot both pass a guard that only saw the
last rendered snapshot, and a `cancel()` that throws is an "unknown" answer
that clears the in-flight flag instead of leaving the confirm inert forever.
Unit tests: "a seeded source never records an event in the future" (scenario
null and every seeded state); E-FLOW asserts no node time later than the
wall clock after a real send.

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

**Corrected in F (review findings, all within the approved design):**

- **Focus never falls to `<body>`.** After a confirmed cancel the cancel
  control unmounts with the pending state, and after the sheet closes itself
  because the restaurant answered, the same; after "track status" /
  "continue" the activated control unmounts with the received view. The
  status card is now the focus target that exists in every state
  (`tabIndex={-1}`, the root's `:focus-visible` ring): the sheet's close
  restores focus to the cancel control if it still exists, else to the card,
  and the in-place switch focuses the card on mount. Focus is restored in an
  effect AFTER the commit that removed the sheet, because the background is
  inert while it is open (next item). Asserted in H22, E-RACE, E-FLOW and the
  cross-engine X01.
- **The cancel sheet is a real modal.** `.head` and `.body` carry `inert`
  while it is open (React 19's boolean prop), so the screen behind it is
  unfocusable and hidden from assistive technology — what the packet's dialog
  rule promises. The sheet is `tabIndex={-1}`: a click on its own body keeps
  focus on the dialog, Escape still keeps the request, and Tab / Shift+Tab
  from the sheet itself enter the cycle at "keep" / "yes" instead of leaving
  the dialog. G35 asserts all three.
- **"30 د" reads number-then-unit.** The body's `{m}` slot was a forced LTR
  island, which in Arabic and Hebrew reads unit-then-number ("د 30").
  CONTENT:221 lists the M:SS countdown as an island, not the minute phrase;
  it is now a `<bdi>` isolate like the restaurant's name, so every locale
  keeps its own order (the prototype flattens it into the sentence, `P:837`).
  G30 asserts the two isolates and no `dir="ltr"` inside the body.
- **The fallback block's controls reach 44 px.** "Open WhatsApp Web" and the
  fallback "Copy message" are 36 px visuals; they now carry the same
  invisible PX-6 overlay as the inline copy control (G29 probes both), and
  "Open WhatsApp Web" is the prototype's `href="#"` (`P:539`): the same
  simulated launch that leaves the visitor ON received with the copy control
  in reach, rather than switching to status and taking the control away.
- **`.cardBody` is not dimmed.** The prototype's `opacity: .92` (`P:556`)
  composited over the danger bed puts the AA-walked `--badText` at 4.18:1 in
  the shipped dark preset: the walk is exact only at alpha 1. The body
  renders at full opacity; a unit test pins the rule and shows the .92
  composite is the failing case.
- **Prototype paint restored on three rules:** the status order summary was
  padded twice (container `4px 14px` AND the list's own `4px 14px` → 8/28 px;
  now `.linesStatus { padding: 0 }`, `P:571`); the bad-tone icon disc and
  terminal node paint their glyph in `var(--badbg)` as the prototype's
  `toneCss` does (`P:839`; 3.62:1 satisfies the 3:1 graphics threshold, and
  `--onBad` stays the ink of the "yes, cancel" fill, PX-3b); the cancel
  control is `var(--bad)` on the page surface (`P:567`; AA in both presets,
  asserted), not the bed-walked `--badText`, which is for text ON the danger
  bed only. `.keepBtn:active { transform: scale(.985) }` was missing.
- **No second viewport.** `.screen` carried `min-height: 100dvh` inside the
  root's own 100dvh column, so with the demo disclosure above it every
  request view scrolled by exactly the disclosure's height. The screen fills
  the root with `flex: 1` alone; E-RESPONSIVE asserts the document equals the
  viewport where the content fits.
- **Reduced motion hides the sheen.** `animation: none` left the sheen's
  `display: block`, a stripe painted across the CTA label; it is
  `display: none` under the media query. E-REDUCED asserts it.
- **"Received is shown once" is enforced by SHOWING it.** The handoff is
  marked seen the moment the received view is chosen, not when the visitor
  leaves it, so Back then Forward renders status for the same send (E-BACK).
  The mount that chose received keeps rendering it from its captured object.

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

## 3.9 Phase F — the ONE integrated final pass

### 3.9.1 What F did

An independent adversarial review of the E implementation (five lenses —
design fidelity, runtime correctness, accessibility/bidi, privacy/truth,
test vacuity — each finding verified by a second reader) returned 32
confirmed findings and 3 refuted ones. Every confirmed finding was fixed
within the bounded scope (no ceiling, comparator, guard or handoff was
touched); the runtime and design corrections are recorded above under the
decision they amend, and the test-side corrections are:

- **G28-EN was vacuous.** It read `innerText` of a DETACHED clone, where
  "sent" and "Copy message" glue into "sentCopy", so the `/\bsent\b/` check
  could not fail — and would have contradicted the LOCKED string table, whose
  preview label is "Message that will be sent". It now reads the rendered
  document (disclosure hidden for the read), asserts the packet's actual
  claim (no sentence states a message WAS sent), pins the future-tense label
  positively, and proves its own detector on a planted past-tense sentence.
- **H21 used the real clock; E-RACE and H19 were wall-clock races.** All
  four now run under `page.clock` (Playwright 1.61): the countdown opens at
  the fixture's 24:10 and moves by exactly the seconds advanced; expiry and
  the late acceptance fire at the instant the SOURCE set and not a tick
  before (a load slower than the 1.5 s margin fails the precondition instead
  of being tolerated); "Copied" reverts at 1,600 ms exactly, not somewhere
  in a 2 s window. The fallback copy control has its own H19 case.
- **E-PRIVACY** now sweeps the received view's own DOM before it is left and
  records every TRANSIENT write (`Storage.setItem`, `pushState` /
  `replaceState`, the cookie setter), not only the final stores.
- **Popups, failed assets and CSP violations** are recorded for EVERY E case
  by a `beforeEach` / `afterEach` net, so "nothing leaves the page" now also
  means no `window.open`.
- **E-CALM** proves the calm preset structurally (class removed in place,
  computed `animation-name` read) instead of asserting the FULL preset's
  class is present.
- The output scan for `wa.me` / `whatsapp://` / `api.whatsapp.com` /
  `bizbot.app` sweeps the JS chunks, where a deep link would actually live,
  and pins the RSC payload count to 4 per request document.

### 3.9.2 The cross-engine smoke (Firefox 1532, WebKit 2311)

G02, G04, G17, G22, G30 and the shortened keyboard-only X01 pass on both
engines (`tests/browser/storefront-ui-001f-cross.spec.ts`,
`playwright.cross.config.ts`, against an EVIDENCE build for G04's
`demo-light` slug). **Playwright's WebKit is not Safari**; a real-device iOS
pass is launch QA outside UI-001.

One engine-specific fact, recorded rather than hidden: the committed CSP
carries `upgrade-insecure-requests`, and WebKit applies it to a plain-http
loopback origin (Chromium and Firefox exempt `127.0.0.1` as potentially
trustworthy, per the spec), so every subresource is rewritten to `https://`
and nothing hydrates. That is a property of the LOCAL server's scheme, not
of the storefront — hosted, the document is https and the directive is a
no-op. For WebKit only, the spec removes that ONE directive from the
document response inside the test (`page.route`, every other directive
kept) and writes that fact into its results file. `vercel.json` and
`serve-out.mjs` are unchanged.

### 3.9.3 Measurements after F (shipped build, `SF_EVIDENCE_ROUTES` unset)

| Measure | After E (cp2) | After F | Cap / plan |
|---|---|---|---|
| `out/` total | 4,001,776 B | **4,002,589 B** (+813) | ≤ 4,194,304 (191,715 B left) |
| Worst first-load JS (cart/checkout/payment/review) | 684,661 / 181,832 | **684,681 raw / 181,839 Brotli** | ≤ 690,000 / ≤ 200,000 |
| Request route first-load | 656,321 / 175,112 | **656,793 / 175,309** | same |
| Largest file | 229,156 | **229,156** (`25u4ugc163b9o.js`) | ≤ 262,144 |
| CSS | 92,771 (2 files) | **93,092** (2 files, +321) | plan 70,000 raw, no validator (owner item, unchanged) |
| Preloaded fonts | 3 files, 77,164 B | unchanged | plan "≤ 2", total ≤ 120,000 (owner item) |

The F reserve (§2.3: 8,000 B) absorbed the whole F increment (813 B of
`out/`, 20 B of first-load).

### 3.9.4 Lab performance protocol (X16) — LOCAL, EMULATED

Chromium, AR Home 390×844, 4× CPU, 1.6 Mbps / 150 ms, 5 runs per transfer
mode, medians (worst in brackets). Raw figures in `perf-lab-raw.json` /
`perf-lab-br.json`; the long-task attribution trace in
`perf-trace-summary.json` (taken on the E build; Home did not change in F).

| Metric | Target | Uncompressed transfer (`serve-out.mjs` as tooled) | Production-like Brotli (lab server) |
|---|---|---|---|
| LCP | ≤ 2,500 ms | **3,028 ms (3,264) — FAIL** | **1,464 ms (1,500) — PASS** |
| CLS | ≤ 0.05 (hard 0.10) | 0 — PASS | 0 — PASS |
| Long tasks, sum of time above 50 ms | ≤ 300 ms | **389 ms (440) — FAIL** | **637 ms (713) — FAIL** |
| Font-swap shift | ≤ 0.02 | 0 — PASS | 0 — PASS |

Read plainly: **the long-task target is not met in either mode, and LCP is
met only under production-like compression.** Neither is hidden behind the
"local, emulated" label; both are carried to the owner with their cause.

- **LCP.** The LCP element is the hero image (`tenant-maps-burger-hero.webp`)
  in every run. Under the repository's uncompressed server the 127 KB
  document alone takes ~0.6 s of the 1.6 Mbps link before the image starts;
  production compresses text (Vercel does), and under that transfer the
  target is met with a 1 s margin. The uncompressed figure is what a
  compression-less host would show and is reported for that reason.
- **Long tasks.** ~~The trace attributes the main-thread time to `Layout`
  (612 ms) and `Paint` (555 ms) … the PR-5 `backdrop-filter` glass on the
  compact bar and dock~~ — **WITHDRAWN (correction pass, §6).** That
  attribution was wrong on two counts the final review caught: the trace sums
  were whole-trace, all-thread totals with nested events double-counted (a
  `RunTask` added to the `Layout` it contains), not main-thread self time in
  the long-task windows; and the glass was not rendering at all in the
  reviewed export (the build kept only `-webkit-backdrop-filter`, which the
  lab's Chromium ignores), so blur could not have been the cause of
  anything. The correct attribution, from the renderer main thread's self
  time inside the > 50 ms windows with a verified paired arm, is in §6.4: the
  first layout, dominated by the `local()` fallback font faces and by laying
  out ~4,300 px of below-the-fold content; blur measured within noise. The
  figure was also noisier than the E-stage trial (raw 269 → 389, br
  563 → 637): a throttled lab on a shared workstation, five runs — the
  spread is in the JSON.

Nothing about these figures is field data; the hosted gate (Lighthouse /
RUM on the real host) is still ahead of any launch.

### 3.9.5 PG-4 final impact check

See `PRIVACY_IMPACT.md` in the pack: no new sink; the E paths were
re-exercised with canaries in every field, on the received view, after a
copy and on the status view, including transient writes; negative controls
for the detector, the contact-identifier source rule and the copy label.

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

_Observations that need no further phase; recorded so the final review does
not rediscover them._

- **Three review findings were not confirmed by their verifiers**; the
  verifiers' own recorded reasons (the workflow journal, quoted in the F
  pack's `review/phase-e-adversarial-findings.json`), not a paraphrase:
  (a) "recreating `source` resubscribes without resetting the snapshot" —
  *"the mechanism the finding describes is accurately read from the code,
  but no reachable input produces the wrong output"*: the only caller,
  `RequestScreen`, passes no `clock`, `statusSource`, `launcher` or `copy`,
  so the memoised identities never change in the delivered runtime (a latent
  hazard for a future caller, not a defect); (b) "under `reactStrictMode` the
  `-late` scenarios never fire" — *"NOT REPRODUCED. The finding's premise —
  that StrictMode runs the subscribe effect mount → cleanup → mount while a
  live source is attached — is false for this component"*: `source` is null
  on the mount render, so the double-invoked effect subscribes to nothing,
  and the live subscription is created by the later `decided` update
  (the earlier wording here, "the export runs no StrictMode double-mount",
  was wrong as a reason and is withdrawn); (c) "E-BACK cannot detect a
  surviving draft" — *"the test therefore does go red on that regression
  (slowly and for an opaque reason), not green"*: with no `actionTimeout`
  the `inputValue().catch()` would auto-wait to the 60 s test timeout, and
  the two-way `/review | /checkout` acceptance was broader than the recorded
  landing. The residual MINOR was fixed in the correction pass: E-BACK now
  waits for `/checkout` exactly and asserts the field exists and is empty.
- The G27 `provenBy` citation in the LOCKED pack points at the wrong
  capture; noted for the pack's owner, the pack is not edited.
- The Hebrew copy has had no native reading pass (pack OQ-3); the 43 E keys
  are included in that debt.
- `ui001f-evidence/` (the cross-engine PNGs and per-engine results) joins the
  earlier per-phase evidence folders as untracked working files; the sealed
  copies are in the pack.
- The evidence folder `ui001e-evidence/` was regenerated by the final pass;
  its PNGs supersede the ones captured before the F corrections (the G35
  sheet capture, for instance, now follows the Tab-from-sheet-body probe).

---

## 6. The final local correction pass (owner-activated, 2026-09-22)

Authority: the owner's activation *OWNER APPROVED — UI-001 FINAL CORRECTION
LOCAL* with the *BIZBOT STOREFRONT — ONE FINAL LOCAL CORRECTION PASS* packet
inline. The bundled review and mandate files it names
(`sources/Pasted markdown(20260922-160953).md`,
`sources/BIZBOT_STOREFRONT_UI_001_FABLE_FINISH_LOCAL.txt`,
`01_FINAL_CORRECTION_Fable.txt`) were not on disk after a bounded search
(Desktop, Downloads, Documents, the repository); the packet's own account of
the findings is the authority for this pass, and that is recorded here and in
the pack's `FINDINGS_DISPOSITION.md`. Starting HEAD `940d8f68`; one
correction checkpoint follows.

### 6.1 DECISION C-1 — ordering is exactly 'open' (review item 1)

One predicate, `submitEligibility` (`checkout/eligibility.ts`), answers every
step control, both entry guards and the send: ordering must be EXACTLY
`'open'` (closed, paused, unresolved and any value this build does not know
refuse), then the visitor's own cart must have been read and priced, then the
cart non-empty, then the details valid for the services offered, then the
total settled. `orderingReason` returns the two existing localised strings
(`orderingClosed {t}`, `orderingPaused`) and nothing invented for
"unresolved". The cart's own control already used the closed / paused
reason; it now reads the same predicate.

- Readiness is LIVE in `FlowRuntime`: it starts as the document's build-time
  state and is read at every render and at the send's activation through a
  ref — a pointer tap, Enter, Space and a forced DOM `click()` reach one
  handler that reads the CURRENT answer, so a stale closure cannot send.
- A closed or paused restaurant never redirects (a redirect would loop: no
  earlier step is "the one where the restaurant opens"). The step renders,
  the form stays editable, the draft and the cart stay untouched, and the
  progression control states the reason; the two prerequisite redirects
  (empty cart → cart, empty details → checkout) stay, and now carry the demo
  token like every other step navigation (a deep link with a readiness token
  was losing it).
- The fixture gateway reads readiness at its COMMIT instant
  (`fixtureGateway({ readiness })`): a send activated while open and
  committed after a close is refused with `{ kind: 'not_open', state }`,
  rendered with the same closed / paused reason as a banner and on the
  control; a send committed before the close stands, and the close never
  erases it (the received view and the status of that request are shown as
  before). A reading the gateway does not know is `server_error`, not a
  fabricated reason.
- The only way readiness can change inside one document in a fixture build is
  a fixture scenario, so three evidence-only tokens exist
  (`closes-late`, `pauses-late`, `opens-late`, 1.5 s, replayed per step
  mount); the shipped tenant is open and the shipped URL carries no token.
- Proof: unit (`sf-flow`: the predicate's table, its order, the reasons in
  three languages, the gateway's commit-time refusal) and browser
  (`storefront-ui-001g.spec.ts`, evidence build, `page.clock`: the open
  positive control with exactly one gateway call; closed and paused direct
  checkout / payment / review with a valid cart; open → closed and open →
  paused after entering the flow, refused at activation with zero gateway
  calls and the draft intact; closed → open admitting the same input;
  commit-time refusal and commit-before-close standing). The reviewed target
  (`940d8f68`) fails the same cases — the cart proceeds to payment on a
  closed restaurant, the send stays enabled after a close — recorded in the
  pack (`logs/negative-control-reviewed-target-940d8f68.log`).

### 6.2 DECISION C-2 — the approved glass is real in the built output (item 2)

The source carried `backdrop-filter` FOLLOWED by `-webkit-backdrop-filter`;
Turbopack's CSS pipeline (lightningcss) on the pinned toolchain treats a
prefixed declaration that follows the unprefixed one as an override and emits
only the prefixed one, which the lab's Chromium ignores — so the export had
no glass. Demonstrated on the pinned toolchain in an owned scratch copy
(prefixed-first: both declarations emitted; source order as reviewed:
prefixed only). The smallest source-only correction: the prefixed
declaration FIRST, the unprefixed one LAST, in the three modules
(`home`, `Intro`, `LanguageMenu`; nine declarations), through the existing
build path — no config, dependency, minifier override, runtime injection or
post-build patch. Proof on a real rebuilt export: nine unprefixed and nine
prefixed declarations served; a non-none computed `backdrop-filter` on every
consumer — hero icon button (10 px), service strip (14), compact header (14),
badge (8), cart dock (14), intro glass button (10), intro pills (10), language
control (10) and its panel (14) — on Chromium, and on Firefox 1532 and
WebKit 2311 for the hero control, strip and dock (both report the unprefixed
property as supported); the geometry the glass sits on unchanged (hero 298,
dock 60); a scratch negative control with the declarations removed is
detected (`computed: none`). No blur fallback is shipped or removed.

### 6.3 DECISION C-3 — CSS and font-preload limits: validators, fonts met, CSS raw not (items 3, 4)

The written limits — CSS per direct-load route ≤ 70,000 B raw AND ≤ 14,000 B
Brotli; font preloads per route ≤ 2 files AND ≤ 120,000 B — are now in
`scripts/budgets.mjs`, measured per route by `scripts/measure-firstload.mjs`
(unique referenced stylesheets, per-response Brotli by the existing method,
inline `<style>` reported separately; `link rel=preload as=font` plus any
`Link`-header preload the committed header set would add, of which there are
none), asserted by `scripts/audit-output.mjs` and by
`tests/output/output.test.mjs` with nonzero-coverage assertions (36 routes,
≥ 1 stylesheet each, 2 preloads on every storefront document) and negative
controls (an oversized stylesheet, a third preload and an oversized preload
set each fail the checker; a planted 80,000 B stylesheet and three preloads
are COUNTED by the measurer).

**Fonts — met.** The pinned `next/font/local` decides `preload` per call and
offers no per-file `unicode-range` or preload, so each subset is its own
call and its own family; the three are composed in `--font` and walked per
character by their script blocks' `unicode-range`. Per root: `/`, `/ar`,
`/en` preload Latin + Arabic (67,816 B) and fetch Hebrew (which carries `₪`)
on demand; `/he` preloads Latin + Hebrew (44,696 B) and fetches Arabic on
demand; the 404 document preloads nothing. Every set is bound one level
below the root layout (the slug layout's wrapper, the request page's prop):
sibling root layouts share one chunk group on this toolchain, so a set
imported by a root layout was linked into every root's documents; the
not-found boundary is part of every route's tree, so the 404 document's own
set holds only on-demand calls of its own; and the arrangement of module
names and import order is load-bearing, because the toolchain's loose CSS
merging absorbs one set into the chunk every document links depending on it
(ten builds, recorded in the pack). Preloading Arabic instead of Latin on
`/he` could not be kept at two preloads for that reason; the Arabic swap on
`/he` is instead made near-invisible by Segoe UI's Arabic metrics
(rubik/segoe widths 98–103 %), which is the system fallback the family list
reaches. Rendering and swap measured: every script renders in Rubik on all
three roots, the on-demand subset is fetched when its script appears, and
the layout shift after `fonts.ready` is 0.00 on AR, EN and HE Home
(G-FONTS). `src/fonts/README.md` records the arrangement.

**CSS raw — not met, structurally, on this toolchain.** Every client CSS
module is merged into ONE chunk that every document links (proven:
`entryCSSFiles` lists the same chunk for every page and for the not-found
boundary; JS is split per route, CSS is not). `experimental.cssChunking:
'strict'` is refused by Turbopack ("only supported with webpack") — proven
by a build in the scratch copy — and switching the bundler is a
`package.json` / `next.config.mjs` change, both protected. The only
storefront-local levers were taken: server-only CSS is per entry, so the
placeholder shell's classes moved from `app/globals.css` into a CSS Module
the placeholder alone imports (−1,155 B on every storefront document); the
scan of unreferenced rules found 42 B, and cross-module duplicate
declaration bodies total ~3 KB — nowhere near the ~24 KB the raw limit
needs. Final: 84,352 B on the flow / request / search documents and
93,989 B on the home / intro documents (the menu documents link the intro's
server-side chunk as well, another loose-merge choice), against 70,000;
Brotli 11,830 / 13,729 against 14,000 — met. The raw axis is carried to the
owner as one decision (§6.6); the validators FAIL on it, as written.

### 6.4 DECISION C-4 — performance: cause found, two candidates, original-mode LCP residual (item 5)

Post-correction measurement first (real glass, corrected fonts, before any
optimisation), then the cause, then at most two candidates, then the final
measurement — all under the unchanged protocol (Chromium, AR Home 390×844,
4× CPU, 1.6 Mbps / 150 ms, cold, 5 runs, medians; original uncompressed
transport as the contract, Brotli supplemental).

| Stage | Transport | LCP | Long tasks > 50 ms (sum) | Long tasks total | CLS | Font swap |
|---|---|---|---|---|---|---|
| Baseline (reviewed, `940d8f68`, glass absent) | uncompressed | 3,028 FAIL | 389 FAIL | 539 | 0 | 0 |
| Baseline | Brotli | 1,464 PASS | 637 FAIL | 868 | 0 | 0 |
| Post-correction (glass real, fonts, ordering) | uncompressed | 2,836 FAIL | 311 FAIL | 411 | 0 | 0 |
| Post-correction | Brotli | 1,408 PASS | 777 FAIL | 927 | 0 | 0 |
| Candidate 1 (no `local()` fallback faces) | Brotli | 1,396 PASS | 472 FAIL | 678 | 0 | 0 |
| **Candidate 2 (+ off-screen sections deferred)** | **uncompressed** | **2,708 FAIL** | **207 PASS** | 307 | 0 | 0 |
| **Candidate 2** | **Brotli** | **1,424 PASS** | **270 PASS** | 420 | 0 | 0 |

Cause analysis (renderer main thread only, self time inside the > 50 ms
windows, nested events subtracted, off-thread parsing excluded; the page's
own `PerformanceObserver` long-task sum agrees with the trace-derived
windows within 3 ms): the windows are ~85 % rendering, ~15 % script (React's
hydration commit in `RunMicrotasks`); the rendering is almost entirely ONE
event, the first `Layout` at DOMContentLoaded — 597 ms in the post-correction
build — plus the full relayout when each preloaded font arrives (~150 ms).
The paired arm with the glass declarations neutralised through the CSSOM
(verified: nine rules changed, computed `backdrop-filter: none`) moved the
sum by ~50 ms (776 → 725) — **blur is not the cause; the earlier
attribution is withdrawn (§3.9.4)**. Hypothesis arms, one neutralised at a
time with the change verified (`perf-arms-br.json`): container queries,
text-shadow, box-shadow, animations, the hero SVG and the images each
changed nothing; removing the two `src: local()` fallback faces (next/font's
generated Arial face and the Segoe UI face this pass had added for Arabic)
cut the first layout from ~590 to ~290 ms — `local()` matching walks the
installed font collection under throttle; removing every `@font-face` cut it
to ~240 ms. **Causality: supported** for the `local()` faces (paired,
verified, reproduced); for the remaining first-layout cost the arm that
removed the off-screen work (candidate 2) is the evidence.

- **Candidate 1:** no `local()` fallback face at all (`adjustFontFallback`
  off, the hand-written faces removed; the family list falls to the system
  list). Design-preserving: the design fixes every line-height, and the swap
  shift measured 0 with and without the metric overrides (lab, G-FONTS).
  Brotli long tasks 777 → 472.
- **Candidate 2:** `content-visibility: auto` with `contain-intrinsic-size:
  auto <size>` on the category sections, the story and the footer — the
  ~4,300 px below a 390×844 first screen. Off-screen layout and paint are
  deferred until a section nears the viewport; what is painted is identical,
  the DOM and the accessibility tree are untouched, anchors and
  `scrollIntoView` render their target on demand, `auto` keeps a rendered
  section's real size. Long tasks 472 → 270 (Brotli) and 311 → 207
  (uncompressed): PASS on both transports. Every browser suite was rerun on
  the final build (§6.7).

**Residual: LCP under the original uncompressed transport, 2,708 ms
(2,648–2,940) against 2,500.** The LCP element is the hero image in every
run; ahead of it the link carries the 128 KB document and 94 KB of CSS
uncompressed. Under production-like Brotli the same page reaches LCP at
1,424 ms. Carried to the owner as one decision (§6.6); no threshold is
changed, no result waived.

### 6.5 The smaller closures (items 6–12)

- The blur attribution: withdrawn in place (§3.9.4) with the forward record
  above; the sealed F report is untouched.
- CSS / font limits: written limits, baseline exceeded (93,092 raw / 12,624
  Brotli; 3 preloads / 77,164 B), final outcome per §6.3.
- H01: no test named H01 existed; the intro of the evidence slugs did not
  even have a document (the intro page pre-rendered the canonical slug
  only). The evidence build now emits the demo slugs' intro documents
  (shipped set unchanged), and `G-H01` asserts closed / paused with the
  right tone, a non-pulsing state dot, and the switched-off service pill,
  with the open intro as the positive control. `FINAL_COVERAGE` had
  claimed "b1 (H01 states)"; that claim is withdrawn in the new coverage map.
- The three not-confirmed findings: §5, reworded to the verifiers' own
  reasons; the E-BACK residual fixed.
- WhatsApp / chat: external navigation stays forbidden. The launcher's typed
  `'simulated'` result is now SURFACED: the demo disclosure is a
  `role="status"` live region that re-issues its one approved sentence
  (a fresh node, so it is announced again) and flashes once on every
  simulated launch — "continue on WhatsApp", "open chat" and the fallback's
  "open WhatsApp Web" (which now keeps the visitor on received with the copy
  control in reach). The sentence never claims a launch; the message preview
  is unchanged by a launch and carries no contact field or note; no popup,
  no request, no navigation (G-CHAT; the reviewed target had `role="note"`
  and no feedback).
- Clipboard: the real-write gate and the exact 1,600 ms are unchanged and
  still asserted (H19, H19 fallback).
- Cross-engine CSP: the WebKit shim is now asserted to differ from the
  committed policy by exactly one directive, and an inline-style negative
  control (an injected `<style>` and a `style` attribute, both refused,
  `securitypolicyviolation` reported) proves the policy each engine received
  is enforced. The public-TLS evidence is not reopened; a self-signed
  transport would be a test limitation, not `bypassCSP` and not proof of
  public TLS. WebKit ≠ Safari stays explicit.
- Hebrew native reading: public-launch QA, unchanged. Arrow / chevron and
  the selected-unavailable disposition: not reopened.

### 6.6 ONE consolidated owner decision (the residual gates)

Two written gates remain unmet after the bounded work, both structural on
the pinned toolchain / protocol rather than defects in the storefront's
behaviour, both measured and validated honestly (the validators FAIL):

1. **CSS per route, raw axis:** 84,352 B (flow / request / search) and
   93,989 B (home / intro) against 70,000 B; the Brotli axis (11,830 /
   13,729 against 14,000) is met. Cause: Turbopack merges all client CSS
   into one chunk per app and refuses strict chunking; changing that needs
   a protected file. Options: (a) accept the raw axis as met by the
   compressed axis for this bundler (the raw limit was written as a proxy
   for transfer; production transfers Brotli); (b) authorise the protected
   change (webpack with `cssChunking: 'strict'` — `package.json` /
   `next.config.mjs`) as a separate ticket; (c) a design reduction of ~24 KB
   of real, referenced rules across the eleven screens.
2. **LCP under the original uncompressed transport:** 2,708 ms against
   2,500 ms (Brotli 1,424 ms). Cause: 222 KB of uncompressed document + CSS
   ahead of the hero image on a 1.6 Mbps link. Options: (a) adopt the
   production-like compressed transport as the acceptance transport for
   LCP (the host compresses); (b) reduce the document ahead of the image —
   the inline RSC payload duplicates the menu (a shared-engine matter, not
   storefront-local); (c) a smaller / lower-priority hero image (a design
   change).

Everything else in this pass passes its gate; nothing was lowered, waived or
relabelled.

### 6.7 Final validation (this pass, one controlled lane, shipped build last)

Filled from the final logs in the correction pack's
`FINAL_CORRECTION_REPORT.md` §3; the pack is the record.
