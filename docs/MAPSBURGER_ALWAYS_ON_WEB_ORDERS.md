# Maps Burger persistent Pickup ordering

Work ID: BIZBOT-MAPSBURGER-ALWAYS-ON-WEB-ORDERS-001.

This release is default OFF. Merging or installing its migration does not open
intake, change the branch's BLOCKED policy, enroll an old request, or send paper.
Activation follows independent review, green CI, and the repository's explicit
human merge gate. Only the owner places and accepts physical acceptance orders.

## Authority and compatibility

The rollout is pinned to organization `20605c2b-3145-4803-a990-bbec3d9c1096`,
restaurant `de3bbc64-edad-4ff4-bccd-c2ef217c1d56`, published branch
`2847c0be-3e31-45a5-957c-508729f1971e`, and slug `mapsburger`.
Delivery and online card payment are not released. Hours are never changed by
activation. OPEN, Pickup availability, current prices/modifiers, quotas, device,
PIN, employee and shift checks remain authoritative.

`public.submit_web_order_live_request(text,uuid,text,jsonb)` is service-only and
uses the existing submission/result shape. The general Edge route calls this
RPC; private-test, pilot and capability-status routes retain their contracts.
Only a fresh successful live submission atomically receives immutable print
eligibility. Historical requests, including previously accepted or expired
tests, cannot acquire eligibility from a timestamp or an acceptance replay.

The existing browse-only profile CHECK remains intact. A separate private
rollout authority supplies the public menu's `ordering_enabled` hint. Neither
that hint, a cached webpage, the slug allowlist nor the Edge flag can bypass the
database gate. Other restaurant rollouts remain OFF.

Installed v63 is unchanged. Its existing exact-target contract is projected from
an automatically allocated, device/session-bound lease. The lease is allocated
atomically with genuine acceptance and binds the accepted decision, canonical
order and initial dispatch. It is never an ordinary print permission. The
branch's global policy stays BLOCKED and the 625 historical holds stay immutable.
Broad pull, ordinary queued imported jobs, and old accepted tests remain excluded.

A five-minute **print lease** is not an intake deadline: the rollout stays enabled
until switched OFF, with no approved-contact or one-customer restriction.
Multiple customers may submit independently. Each allowed device has one active
acceptance/print slot; a concurrent acceptance on that device is refused before
canonical creation until its earlier attempt is terminal or its unsent lease
expires. The existing v63 `order_rejected` error is used as a retryable refusal;
it does not create a rejected decision or consume the still-pending request.
The cashier should refresh that request after the current print operation ends.

Fresh genuine readiness is still required before claim. The unchanged bounded
spool initialization never drains old jobs or resets a nonempty database/key.
Irreversible begin reserves at most one automatic transmission. A crash, lost
reply or uncertain send is reconciliation work, never permission to resend.
An unfinished reserved attempt blocks another acceptance on that device even
after lease expiry. No automatic retry or alternate printer fallback is added.

## Release and activation

Use the established privileged operator connection, not an app/service-role
workaround. Do not place credentials in SQL files, logs or client bundles.

1. Recheck approved source/CI, hosted migration history, exact 625 hold IDs and
   fingerprints, BLOCKED revision 1264, old target identities and admission OFF.
   Stop on unexplained drift. Preserve the existing official APKs and devices.
2. Install only the reviewed additive migration. Verify its four private tables
   are empty, forced RLS/privilege denial, the service-only live RPC, and no
   modifications to profile, holds, old requests/orders/dispatches or channels.
3. Deploy the compatible existing `web-order-submit` gateway with
   `verify_jwt=false`, keeping general/test/pilot flags false and permit absent.
   Anonymous gateway access still delegates all authority to validated server
   credentials, strict request validation, exact CORS and the private DB gate.
4. Deploy the reviewed live Storefront to the existing `bizbot-storefront`
   project. Verify READY, source identity and `menu.bizbot.systems` alias binding.
   Browse-only must still work before activation; do not submit a smoke order.
5. In one bounded READ COMMITTED operator transaction, enable the rollout using
   the exact verified v63 device allowlist, then enable only the existing scoped
   channel row without resetting its quota counters. Initial allowlist: HOME
   `bb80c0d8-6893-4e24-8eea-5a14cf545ecd` only. No other device is silently
   certified or updated. No ordinary or target-only branch policy is appended.
6. Set `WEB_ORDERS_ENABLED=true`, `WEB_ORDERS_TEST_ENABLED=false`, and
   `WEB_ORDERS_PILOT_ENABLED=false`; keep `WEB_ORDERS_TEST_PERMIT` absent.
   Verify secret metadata safely, the live menu hint and the actual custom-domain
   cart/checkout/review flow. Do not submit on the owner's behalf.
7. The owner submits distinct orders, accepts on the allowed v63 POS and reports
   actual paper, selected POS language and preparation totals above the items.
   Read-only evidence reconciles each request/decision/order/dispatch/attempt.
   Do not claim physical acceptance from Bluetooth/database success alone.

The operator-only configuration function is:

```sql
app.set_mapsburger_web_orders(
  p_intake_enabled boolean,
  p_print_enabled boolean,
  p_allowed_device_ids uuid[],
  p_reason text,
  p_operator_reference text
) returns bigint
```

All configuration/evidence is private and append-only. There is no public
activation RPC. A later containment revision invalidates the rollout until the
operator explicitly reconciles and reauthorizes its protection baseline.

## Immediate OFF and rollback

Intake OFF is server-enforced at commit, even while old HTML still shows Submit.
Use this exact operator transaction for HOME-only intake OFF:

```sql
begin isolation level read committed;
select app.set_mapsburger_web_orders(
  false, true,
  array['bb80c0d8-6893-4e24-8eea-5a14cf545ecd'::uuid],
  'Owner requested new intake OFF',
  'BIZBOT-MAPSBURGER-ALWAYS-ON-WEB-ORDERS-001:OFF'
);
commit;
```

It atomically closes the scoped channel, preserves admitted identities, status
capabilities and the existing print generation. Already admitted requests may
still be accepted and printed through their exact leases. Confirm the live RPC
denies new admission and status reads still work. Then set the general Edge flag
false as defense in depth. Do not delete pilot/rollout evidence or reset quotas.

For an emergency print stop, call the same function with `false, false` and an
explicit incident reason. This revokes future claim/begin authority; it cannot
recall bytes already transmitted or turn an uncertain outcome into a safe retry.
Re-enabling after emergency print OFF creates a new generation, never reviving
old eligible requests. Preserve those requests for reconciliation.

Rollback closes intake before restoring an earlier frontend or gateway. Retain
the additive schema, all customer status access, immutable holds, accepted
orders and send-reservation evidence. Never use ordinary mode, broad replay,
fabricated ACKs, data deletion or APK changes as rollback mechanisms.

The cold-offline imported-spool limitation remains unapproved for commercial
fleet rollout. This targeted online path does not grant offline imported work
authority or change genuine direct/offline POS orders.
