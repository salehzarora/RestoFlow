# BIZBOT-STOREFRONT-MANUAL-ORDER-PILOT-001

Owner-authorized, short, owner-operated Maps Burger Pickup pilot. Codex must
never submit the live order. No ordinary printing or commercial fleet rollout.
Kitchen labels retain Android/device language; saved product/modifier/note
content is unchanged. No native application or APK changes.

## Capability and authority

- Existing general release remains OFF (`LIVE_ORDERING_RELEASED=false`).
- Exact Maps Burger slug alone may display its server ordering bit. Live reads
  bypass ISR for this slug; other tenants retain their existing caching/gate.
- Private `app.storefront_manual_order_pilots` has forced RLS and no client or
  service-role table privileges. No row or channel is activated by migration.
- One privileged operator record pins organization, restaurant and branch,
  salted owner-approved name/E.164 phone hash, and a server deadline <=15 minutes.
- `WEB_ORDERS_PILOT_ENABLED` is explicit/default-OFF. General/test/pilot Edge
  gates cannot coexist. Only the service-only pilot RPC authorizes intake.
- First successful request atomically consumes the lifetime budget and disables
  the pilot/channel. Distinct UUIDs cannot create another request. Exact original
  SQL replay and independent customer status remain recoverable after closure.
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
   paper, all other capable clients stopped. Require 624 unchanged holds,
   BLOCKED revision1258 baseline, no unheld candidates or pending request. Preserve
   the failed v61 and already printed v62 request/order/dispatch/attempt unchanged.
4. Privately hash only the approved retained contact. Enable only the pilot Edge
   gate (general/test=false, test permit absent). Under the exclusive branch
   containment lock, revalidate protection and insert the one bounded initially
   enabled pilot record plus enable only the existing exact branch channel.
   Disabled records cannot be rearmed. Never relax the profile CHECK.
5. Verify public menu ordering=true and actual website cart/checkout availability
   without submitting. Give owner https://menu.bizbot.systems/s/mapsburger/menu.
   Owner selects products, enters approved contact and submits manually once.
6. Observe atomic pilot/channel closure, disable the Edge pilot gate and verify
   no new intake. Preserve status and consumed identity. Recognize the owner's
   browser request/reference and contents; never select an unrecognized visitor.
7. Verify one pending request, no decision/canonical/dispatch/attempt. Obtain its
   INTERNAL UUID. Only then append a short exact target_only policy with all624
   holds retained. Tell owner to press Accept ONCE on HOME.
8. Observe fresh secure-spool readiness and exact claim/begin/finish. One begin
   can authorize at most one automatic transport attempt. No old-job drain,
   resend, manual reprint, key reset or fallback transmission is allowed.
9. Obtain owner paper count and expected versus observed preparation summary,
   item quantities/modifiers/notes. Transport success alone is not paper proof.
10. In a finally/uncertainty path append explicit BLOCKED, close pilot/channel,
    disable the Edge pilot flag; verify all624 holds/source rows and prior orders
    unchanged. Preserve this test and audit trail, even on failure. Stop.

## Abort and kill

Missing security/readiness/owner recognition means STOP, not an improvised
workaround. Lock/update the pilot before the channel, matching submission order.
Disable the pilot and channel without deleting consumed identity. Set pilot Edge
flag OFF; status remains available. Server expiry and atomic budget deny new
requests even if Codex exits or a browser still displays stale checkout.

Uncertain submission: reconcile the same browser identity/capability; never
replace it. Uncertain begin/send or no paper: preserve attempt and reconcile,
never resend. No ordinary policy or other-device restart is part of this pilot.
Cold-offline imported-spool behavior remains unapproved for commercial rollout.
