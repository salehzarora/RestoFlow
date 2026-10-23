# Acceptance estimate and receipt display — BIZBOT-STOREFRONT-ACCEPTANCE-ETA-001

Issue #360; implementation baseline `d796ec4b8be73fa70b9c93cfa8765cbd67f3d45a`.

## Adopted contract and authority

The owner approved the R2 proposal and the implementation decisions below after
the Featured-products rollout. The preserved proposal is
[`contracts/BIZBOT_STOREFRONT_ACCEPTANCE_ETA_R2.txt`](contracts/BIZBOT_STOREFRONT_ACCEPTANCE_ETA_R2.txt),
SHA-256 `d7fc4c38b5e87fa163ef0fc7d22deb7c12bbcb157526ce23f18854672d8ad550`.
Its historical “proposed / no implementation” status describes its creation;
this document records the subsequent owner approval. The external original
remains unchanged. This task authorizes implementation, tests and a review PR.
It does **not** authorize an ETA production migration, deployment or APK build.

- Quick choices: 10, 15, 20, 30, 45, 60 minutes. Custom: integer 1..240.
  No implicit selection. Confirm Accept is explicit; cancel/dismiss sends nothing.
- One private immutable sidecar, atomic with the winning acceptance and original
  canonical/dispatch effects; no historical backfill or subsequent ETA editing.
- Named `pos_accept_web_order_with_eta` and `get_web_order_request_status_v2`
  RPCs preserve existing callers, authorization and legacy response shapes.
- Optional accepted-only `acceptance_eta` has exactly `preparation_minutes`,
  `accepted_at`, `ready_at`, `timezone`. UTC instants bind the original decision;
  timezone is the validated effective branch/restaurant IANA zone captured then.
  Replay never looks up a replacement timezone or restarts the duration.
- The customer sees an approximate duration and absolute ready time/date in that
  stored zone. No countdown or automatic “ready” transition.
- `X-BIZBOT-Order-Response-Version` is a non-authorizing representation header.
  Absent/exact `1` always retains legacy JSON, including old tabs observing a new
  ETA acceptance. Exact `2` is status-only. Empty, malformed, duplicate/comma-joined
  or unsupported values fail before RPC; submit with `2` fails before writes.
- Every valid negotiated status response after its action is known acknowledges
  `2`: pending, accepted, rejected, expired, fixed errors and unavailable outcomes.
  Invalid origin/method or unreadable body before action discovery retains the
  existing outer error without acknowledgment; invalid version/submit-2 also
  receives no acknowledgment. CORS allows/exposes only the added version header,
  `Vary` includes Origin and the header, all representations/errors are no-store.
- The new browser validates acknowledgment without a silent legacy fallback.
  Submit body/identity/recovery storage remain unchanged. An accepted submit
  replay may cause one bounded negotiated status read; a failed read preserves
  the confirmed accepted state and cannot trigger another submission.
- POS freezes original decision identity and selected duration through existing
  bounded reconciliation using the real session-guarded/HOLD/upgrade transport.
- Receipt phone formatting is display-only, shared by receipt and preview:
  valid Israeli numbers display locally; other international values, canonical
  storage, dialing, print authorization and kitchen ACK behavior remain intact.

## Isolation and verification

Separate SQL, Edge and POS branches/worktrees feed this integration branch.
No exact source overlap with open printer PRs #314/#315 was found; downstream
raster regressions remain required. Shared payment documentation owned by open
PRs #362/#363 is not changed. No signing/version-ledger change is in scope.

Required evidence includes actual rollback after injected metadata failure,
concurrent winner/loser behavior, capability/quota parity, old-open-tab and mixed
client compatibility, the acknowledgment matrix, uncertain-intent recovery,
keyboard/RTL chooser tests and display-only receipt tests. Local/CI evidence
must remain separate from owner physical acceptance.

## Implementation and local verification

The additive migration is
`20261022014650_bizbot_storefront_acceptance_eta_001.sql`, SHA-256
`560a180af68e92fd24383aaec742f90ba466d576b70b4d02b5993a8757e03567`.
The new wrapper takes the existing route's containment/device/context/request
locks in the same order, validates the pending request's timezone, then delegates
to the original accept exactly once. Its enclosing subtransaction includes the
private metadata insertion. The versioned intent fingerprint does not change the
legacy decision fingerprint. Accepted replay uses the stored scope, winner,
duration and timezone; legacy acceptance cannot acquire a retrospective ETA.

Local results, before any ETA deployment:

| Layer | Actual result |
| --- | --- |
| PostgreSQL authority, metadata, rollback and status | 95/95 pgTAP assertions |
| Independent database connections | 106 assertions / 9 race groups |
| Storefront, customer/decision Edge, dispatcher and scheduler | 851/851 Node tests, 0 skips |
| POS chooser, intent/recovery and receipt tests | 222 focused + 51 preservation + 54 printing-package tests |
| Final integrated real boot/guard/SDK/updated Edge | 23/23, including ETA six-argument RPC once |
| Storefront typecheck, fixture build and output checks | PASS / PASS / 28/28 |
| Focused POS analyzer and l10n guard | PASS |

The metadata-failure probe first verifies that the real canonical order, items,
decision, dispatch and lease exist inside the transaction, then raises. Tests
prove their rollback, including audit/sync effects and the pending request's
original mapping. Independent before/after full-function-definition hashes match
for all five legacy writer/reader functions. The separate end-of-fixture body
assertion alone is not used as proof of migration preservation.

Races cover distinct devices, identical replay, changed duration, a rolled-back
winner, legacy acceptance, PIN revocation during lock wait, post-channel-lock
status visibility, and both acceptance/rejection winner directions. They use a
fresh local schema clone, fixed Docker Unix socket and synthetic identities.

The preserved old transport source is SHA-256
`63c078473211d3deb9d1d522533205343acdd69cb0ee606d3faf37ad5d87f288`;
it matches the unchanged pre-ETA source and is actually instantiated, retained
across the backend switch and exercised against the updated handlers. The final
RPC boundary in those JavaScript/Flutter composition tests is synthetic;
database authority is tested separately above. This is not physical/browser
production acceptance. Existing failed synthetic fixture runs are preserved;
their corrections did not relax production authorization or success gates.

Independent Edge, Storefront, POS/receipt and database/security source reviews
approved their respective scopes. Full required PR CI is an additional gate;
local Windows evidence does not claim Linux CI success.

## Later rollout gates

After exact-source review and separate authorization: additive SQL first;
backward-compatible negotiated customer and decision Edge support second;
verified Storefront consumer third; reviewed POS release last. Do not activate a
consumer before its actual backend acknowledgment/CORS contract is verified.
Never roll back committed orders, delete sidecars, repair history or replay a
print to resolve an uncertain outcome. Reconcile authoritative state instead.

Ordering, notifications and Cron remain ON. Preserve merchant content/phone,
v68, pairings/local data, BLOCKED revision 1264 and all 625 protected holds.
No agent-created production orders, calls or printing. The earlier mock-harness
incident retains UNKNOWN connectivity; it is not reused here.

Issue #360 remains open: Home promo/story/category controls, visual and
multi-restaurant journey acceptance, ETA physical acceptance and the compatible
POS release remain tracked. v69 is a bookkeeping reservation, not build approval.
