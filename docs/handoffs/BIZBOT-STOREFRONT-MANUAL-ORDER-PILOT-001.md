# BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001

Owner-authorized, short, owner-operated Maps Burger Pickup pilot. Codex must
never submit the live order. No ordinary printing or commercial fleet rollout.
Kitchen labels retain Android/device language; saved product/modifier/note
content is unchanged. No native application or APK changes.

## Capability and authority

- Existing general release remains OFF (`LIVE_ORDERING_RELEASED=false`).
- Exact Maps Burger slug alone may display its server ordering bit. All tenants
  retain the existing 60-second ISR/360-second bounded-stale route contract.
  Actual admission is always checked against the database clock and one-request
  budget, regardless of a cached document's ordering hint.
- Private `app.storefront_manual_order_pilots` has forced RLS and no client or
  service-role table privileges. No row or channel is activated by migration.
- One privileged operator record pins organization, restaurant and branch,
  salted owner-approved name/E.164 phone hash, and a server deadline <=15 minutes.
- `WEB_ORDERS_PILOT_ENABLED` is explicit/default-OFF. General/test/pilot Edge
  gates cannot coexist. Only the service-only pilot RPC authorizes intake.
- First successful request atomically consumes the lifetime budget and disables
  the pilot/channel. Distinct UUIDs cannot create another request. Exact original
  SQL replay and independent customer status remain recoverable after closure.
- A closed, unused window may be followed by a fresh window of at most 15
  minutes. Every old row and deadline remain immutable. Only one window may be
  enabled, and one successful request consumes the branch's budget across all
  windows. A consumed window cannot be renewed automatically.
- After the first unaccepted request genuinely expires, the owner may authorize
  ONE additional request using migration20261016202838. Its empty/default-OFF
  private singleton authorization binds one exact future pilot UUID, expired
  predecessor pilot/request, scope, <=15-minute deadline and owner reference.
  Authorization and its exact window must commit together. No historical row
  is rewritten/deleted; no third allowance can be minted. Old/new exact replay
  retains original identity and the existing abuse accounting. A decision,
  canonical mapping, targeted enrollment or unexpired predecessor refuses it.
- Profile browse-only CHECK and stored ordering/delivery flags stay intact.
  The reader overrides only the existing public ordering bit while pilot/open/
  pickup/channel/BLOCKED predicates hold. No public JSON field is added.
- Existing input validation, price/modifier/tax authority, quotas, pending-only
  writer, POS acceptance and targeted at-most-once print fences are unchanged.

## Preparation-count evidence

Trusted item/modifier snapshots pass through canonical acceptance and dispatch.
Modifier quantity and line quantity each multiply once. Resource and cheese
classification group totals without multiplying again. Canonical rendering
places the preparation summary above the items.

Read-only live catalogue: six burger products have bread=1. Classic, Arabic,
Mexican and Smash have active 120/240/360/480g meat contributions 1/2/3/4.
Italiano has active 120/240/360g; its 480g option is deleted and must stay excluded.
Crispy has bread, with no configured meat contribution. Counts must never be
inferred from names or invented. Two Classic 240g burgers contribute four meat
pieces and two bread units, classified by their actual cheese selections.

Rollback-only SQL regression covers mixed normal/Smash resources, with/without
cheese, item quantity and modifier quantity through real submit/Accept/dispatch.
Existing adapter/renderer tests cover aggregate counts and summary placement.

## Bounded execution sequence

1. Complete focused regressions, independent review and normal CI. Verify exact
   deployment project/source/environment. Keep all admission OFF during install.
2. Apply only migration 20261016144418, verify its private ACL/RLS and zero pilot
   rows. Update existing web-order-submit identity, verify_jwt=false; preserve
   media publisher JWT verification. Deploy compatible Storefront in the same
   existing project/domain, preserving live-read settings and protection.
3. Reconfirm owner HOME v62/PIN/open shift, saved reachable HOME printer with
   paper, all other capable clients stopped. Require 625 unchanged holds, including
   the original624 and the separately owner-approved exact additional dispatch.
   Raw BLOCKED policy1258 / effective revision1260 is the updated baseline.
   One separately observed ordinary HOME dispatch remains untouched:
   `6759a993-a2b2-4e4b-ba77-1cabaa527e78`, full-row MD5
   `77820902516d988eced9db0e67d380b5`. Its physical outcome is UNKNOWN.
   Exact target authorization excludes that row; independent direct/local POS
   printing has separate authority. Require no other unheld candidate, no
   pending request and HOME idle except the one Inbox acceptance. Preserve
   the failed v61 and already printed v62 request/order/dispatch/attempt unchanged.
4. Privately hash only the approved retained contact. Enable only the pilot Edge
   gate (general/test=false, test permit absent). Under the exclusive branch
   containment lock, revalidate protection and insert the one bounded initially
   enabled pilot record plus enable only the existing exact branch channel.
   Disabled records cannot be rearmed. For renewal, apply only additive
   migration 20261016184616 after its focused checks/review/CI; preserve the
   expired row byte-identically, verify no consumed identity and insert a new
   bounded row under the same lock. Never relax the profile CHECK.
5. Verify public menu ordering=true, then allow existing ISR to refresh and verify
   actual nonempty website cart/checkout form availability without submitting.
   Do not tell the
   owner to order based only on the database bit; require the rendered checkout
   to be available with sufficient time remaining in the bounded window.
   Give owner https://menu.bizbot.systems/s/mapsburger/menu.
   Owner selects products, enters approved contact and submits manually once.
6. Observe atomic pilot/channel closure, disable the Edge pilot gate and verify
   no new intake. Preserve status and consumed identity. Recognize the owner's
   browser request/reference and contents; never select an unrecognized visitor.
7. Verify one pending request, no decision/canonical/dispatch/attempt. Obtain its
   INTERNAL UUID. Only then append a short exact target_only policy with all625
   holds retained. Tell owner to press Accept ONCE on HOME.
8. Observe fresh secure-spool readiness and exact claim/begin/finish. One begin
   can authorize at most one automatic transport attempt. No old-job drain,
   resend, manual reprint, key reset or fallback transmission is allowed.
9. Obtain owner paper count and expected versus observed preparation summary,
   item quantities/modifiers/notes. Transport success alone is not paper proof.
10. In a finally/uncertainty path append explicit BLOCKED, close pilot/channel,
    disable the Edge pilot flag; verify all625 holds/source rows and prior orders
    unchanged. Preserve this test and audit trail, even on failure. Stop.

## Abort and kill

Missing security/readiness/owner recognition means STOP, not an improvised
workaround. Lock/update the pilot before the channel, matching submission order.
Disable the pilot and channel without deleting consumed identity. Set pilot Edge
flag OFF; status remains available. Server expiry and atomic budget deny new
requests even if Codex exits or a browser still displays stale checkout. A stale
checkout hint cannot bypass the server gate and may remain until normal ISR.

Uncertain submission: reconcile the same browser identity/capability; never
replace it. Uncertain begin/send or no paper: preserve attempt and reconcile,
never resend. No ordinary policy or other-device restart is part of this pilot.
Cold-offline imported-spool behavior remains unapproved for commercial rollout.


## Owner-authorized additional attempt / operating restaurant

The owner subsequently authorized another website order after the first pilot
request expired unaccepted, and explicitly allowed the restaurant to continue
operating during the test. This supersedes the earlier requirement to quiesce
all other clients for this specific manual pilot. Restaurant OPEN is a service
state, separate from device operation. Do not falsely report fleet quiescence.

Keep the original624 and separately approved625th hold immutable, ordinary
server-imported printing BLOCKED and prior web targets excluded. Ongoing
ordinary orders/dispatches and legitimate order-status updates must be recorded
as normal restaurant activity, not held, acknowledged or silently removed.
Any original held-dispatch drift or prior target claim/send drift still stops
this pilot. The new test may authorize only its genuine internal request ID;
existing global claim/begin fencing permits at most one automatic transmission
across eligible devices. Do not promise which printer wins. Tell restaurant
operators not to Accept the labeled TEST request; the owner Accepts once on
HOME only after exact target authorization. Premature acceptance, an uncertain
submission or send, no paper, or any unexpected prior target activity means
reconcile and stop, never a replacement or automatic resend.

The extra allowance is a singleton, not a reusable release gate. Install only
its reviewed additive migration while all admission stays OFF. In one bounded
privileged transaction under the exclusive branch fence, verify the exact
expired unaccepted predecessor and unchanged protection, then insert the
immutable authorization and exact new pilot window. The existing approved
contact binding remains private. There is no Edge/Storefront/APK contract change.
Reconfirm owner/cart presence and remaining service time BEFORE opening this
window. First successful browser submission atomically closes pilot/channel;
then disable the Edge pilot flag and verify closure before target-only policy.
An expired predecessor remains preserved and cannot be accepted or reused.

## One replacement for the unused additional window

The additional window was explicitly closed without creating a request after
the owner reported a different contact spelling/phone. It remains immutable.
Migration `20261016215837` installs only an EMPTY/default-OFF singleton retry
authorization and extends the existing private allowance predicate. It does
not activate checkout, modify the submit RPC or add a successful-order budget.

The replacement must bind the exact closed, wholly unconsumed extra pilot and
its original allowance, identical approved contact salt/hash, exact new pilot
UUID, Maps Burger scope, operator reference and a new <=15-minute interval.
Authorization and the future pilot commit together under the exclusive branch
fence; BLOCKED and no active pending request are required. Old authorization,
pilot deadlines, requests and audit rows remain unchanged. A consumed extra,
orphan binding, changed contact, second retry or further successful request is
denied. The parent plus the original-extra/replacement pair can create only
two total requests: the expired predecessor and ONE additional request.

Before opening this last replacement, require the owner to have the exact
approved contact and cart ready. Use the existing new-order/recovery controls;
never reset an uncertain browser request identity. Open only the short window,
verify rendered checkout, and have the owner submit once. A rejected contact
does not consume a request; preserve the same browser identity and reconcile.
Server expiry, the one-success fence and explicit close remain authoritative.
After a genuine pending request is identified, close all new intake before
binding target-only authority. Any acceptance and paper observation remain
manual owner actions. No automatic renewal or unrestricted ordering is added.

Focused verification: new retry pgTAP plus unchanged pilot/additional-allowance
regressions, actual concurrent writer/expiry/operator-close races, private ACL
and history retention checks, one independent review and normal CI. No Inbox,
audio, SQLite, Bluetooth or APK baseline test is repeated.
