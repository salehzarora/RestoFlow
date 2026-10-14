# STOREFRONT-ROLLOUT-001C-PREP — controlled pickup test

Status: preparation only. This PR does not authorize merge, hosted migration,
Edge deployment, secret changes, channel creation, a real request or activation.
Every production action below requires the next explicit owner authorization.

## Verified target and feasibility

- Project: `oqmevrndtivqxgyvcmwy`; slug: `mapsburger`.
- Organization: `20605c2b-3145-4803-a990-bbec3d9c1096`.
- Restaurant: `de3bbc64-edad-4ff4-bccd-c2ef217c1d56`.
- Branch: `2847c0be-3e31-45a5-957c-508729f1971e`.
- One predetermined client request UUID: `922b6772-0423-4310-9c17-9ad249f6cd72`.
- Starting source: `ed7779bf9b062ffb9c1bf09a11155931545d96ac`.
- At preparation: 157 migrations; no web-order channel/request/event/decision;
  general Edge gate OFF; public ordering/delivery OFF; service `closed`.
- The branch uses `printer_only`. Reconfirm it immediately before the test.

There is no preexisting private test admission. Existing SQL submission/pricing
and POS acceptance do not require public `ordering_enabled=true`: they require
an eligible published, actually open, pickup-capable menu and current valid
prices. New submission additionally requires its exact branch channel enabled.
Therefore this backend test needs neither a public checkout release nor a
profile CHECK relaxation. Do not change either. Do not change opening hours or
force a false open state to get past this precondition.

The Edge permit hashes a separate private 256-bit bearer, customer capability
and normalized order. It pins the full scope, one UUID and an absolute window
(recommend 10 minutes; hard limit 15). The small service-only SQL wrapper locks
and checks authoritative scope and time before invoking existing submission;
expired work rolls back. There are no new tables, public grants or canonical
writers. The existing channel, pricing, idempotency and abuse controls still
apply. Origin, an unpublished URL and the disabled checkout button are not
authentication.

## Operator procedure — next owner authorization only

1. **Release prerequisites.** After review, merge and separately authorize the
   new guard migration and compatible Edge release. Keep `verify_jwt=false` for
   this gateway and media publishing JWT-protected. Verify the guard exists,
   `WEB_ORDERS_ENABLED` is absent/false, test mode is OFF, all channels are OFF,
   and no earlier request uses the fixed UUID. Do not repeat installation during
   the actual order test.
2. **Owner hardware/session confirmation.** Owner confirms the real paired POS
   device for this branch, active employee/PIN session, required role, open shift,
   printer bridge, correct assigned kitchen printer and physical paper/connection.
   Do not create or impersonate a device, employee, PIN session or shift.
3. **Actual service and approved payload.** Read `public.storefront_menu('mapsburger')`;
   require `ok=true`, `service.state='open'`, pickup enabled and the exact profile
   scope above unchanged. Require branch `kitchen_workflow_mode='printer_only'`.
   Owner approves the test name and E.164 phone, one labeled pickup order,
   quantities, available item/modifier IDs and both item/order notes. Include
   `[CONTROLLED TEST — STOREFRONT-ROLLOUT-001C]` in order notes. Choose a window
   safely within opening hours. Do not add payment or delivery.
4. **Prepare private material offline.** In an owner-only, access-restricted local
   directory **outside Git and deployment upload roots**, keep the approved
   `order.json`. Generate independent 32-byte CSPRNG values for the bearer and
   status capability, canonical unpadded base64url. Construct one `request.json`
   using the fixed UUID above, `action:'submit'`, `slug:'mapsburger'`, that status
   capability and approved order. Use the existing `validateRequest` to compute
   the normalized-order digest. Build the permit with the exact contract keys
   and UTC `not_before`/`expires_at` (10 minutes). Store the original request and
   bearer privately. Do not print them, use shell-history assignments, put them
   in command arguments/URLs, attach them to evidence, or enable HTTP debug logs.
5. **Open only the protected test window.** The authorized release operator sets
   `WEB_ORDERS_ENABLED=false` and installs the digest-only permit plus
   `WEB_ORDERS_TEST_ENABLED=true` through the existing secured secret workflow.
   Use a protected env file/normal CLI ingestion, never inline credentials.
   Enable only the scoped Maps Burger SQL channel using the exact DML below.
   Verify all other channels remain disabled and ordinary unauthenticated submit
   still returns `503 ordering_unavailable`. Do not touch the public checkout
   gate, profile CHECK, products, prices, POS or printing code.
6. **Submit once.** A private operator process reads the original request and
   bearer from protected local storage and HTTPS POSTs to the existing endpoint:
   `https://oqmevrndtivqxgyvcmwy.supabase.co/functions/v1/web-order-submit`.
   Use `Content-Type: application/json`, `Authorization: Bearer <private bearer>`,
   no cookies and no redirects. Do not print headers/body. Require a genuine
   `ok:true,status:'pending',replayed:false` receipt. On timeout/uncertain outcome,
   **stop submissions and reconcile by capability status first**; never generate
   a second UUID, capability or altered payload. If absent status is inconclusive
   because the first call may still be running, inspect the recorded identity
   read-only before considering an exact replay within the permit window.
7. **Prove pending is not canonical.** Read only the fixed request: require one
   pending row, `canonical_order_id IS NULL`, a received event, no decision and no
   mapped canonical order/print dispatch. Verify its captured scope, quantities,
   modifiers, notes and authoritative totals against the approved payload.
8. **Cashier accepts.** The owner/cashier opens the genuine Online Orders Inbox,
   checks the labeled test and its details, and presses Accept once using that
   real POS session. If the POS reports uncertainty, use its existing recovery
   flow and stable decision identity; never call privileged acceptance directly.
9. **Prove acceptance and physical print.** Require one accepted request, one
   accepted decision and exactly one mapped canonical order. Check actual
   canonical items, modifier quantities, item/order notes and totals. Require
   existing `direct_print` dispatch behavior and exactly one
   `kitchen_print_dispatches` row for the canonical order. Inspect the snapshot
   read-only. **Owner confirms the correct paper ticket physically printed once**;
   a dispatch row, bridge claim or printer ACK alone is not proof of paper.
10. **Status and exact replay.** POST `action:'status'`, the same slug, UUID and
    private status capability, without `order` or test bearer. Require `accepted`.
    Within the permit window, replay the byte-identical original submit once:
    require `replayed:true`, `accepted`, the same request identity, and unchanged
    canonical order/decision/dispatch counts (one each). Never create a second
    test request. After expiry use status reconciliation, not a renewed identity.
11. **Close immediately, including on failure.** Set `WEB_ORDERS_TEST_ENABLED=false`,
    remove the permit, and set/retain `WEB_ORDERS_ENABLED=false`. Disable the
    target channel with the exact scoped UPDATE below. Verify disabled submission
    rejects, no channels remain enabled, public checkout/delivery remain OFF, and
    the original status capability still reports the real result.
12. **Preserve evidence and audit.** Retain the test request/order, received and
    accepted events, decision, canonical rows and dispatch. Record safe IDs,
    counts, totals and the owner's paper confirmation; omit contacts, bearer and
    status capability from shared evidence. Never delete, rewrite, void, reprint
    or record a payment as cleanup. Any subsequent accounting action needs its
    own owner decision. Keep the disabled channel row so status remains readable
    during its existing 24-hour lifetime.

## Exact future channel writes — not executed during preparation

Run only after the next production authorization and preflight. The WHERE guard
on conflict must affect exactly one correctly scoped row; otherwise STOP.

```sql
insert into public.web_order_channel_settings
  (organization_id,restaurant_id,branch_id,submission_enabled)
values ('20605c2b-3145-4803-a990-bbec3d9c1096',
        'de3bbc64-edad-4ff4-bccd-c2ef217c1d56',
        '2847c0be-3e31-45a5-957c-508729f1971e',true)
on conflict (branch_id) do update set submission_enabled=true
where web_order_channel_settings.organization_id=excluded.organization_id
  and web_order_channel_settings.restaurant_id=excluded.restaurant_id;

-- Switch-off: preserve the row and all request/status/audit data.
update public.web_order_channel_settings set submission_enabled=false
where organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'
  and restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'
  and branch_id='2847c0be-3e31-45a5-957c-508729f1971e';
```

## Read-only receipts for the single identity

Use normal authorized operational SQL access; never expose table grants or
service credentials to the customer/POS. Read these receipts before acceptance,
after acceptance, after replay and after switch-off:

```sql
select w.id,w.status,w.canonical_order_id,
  (select count(*) from public.orders o where o.id=w.canonical_order_id) canonical_orders,
  (select count(*) from public.web_order_decisions d where d.request_id=w.id) decisions,
  (select count(*) from public.kitchen_print_dispatches d
    where d.order_id=w.canonical_order_id) printer_dispatches
from public.web_order_requests w
where w.organization_id='20605c2b-3145-4803-a990-bbec3d9c1096'
  and w.restaurant_id='de3bbc64-edad-4ff4-bccd-c2ef217c1d56'
  and w.branch_id='2847c0be-3e31-45a5-957c-508729f1971e'
  and w.client_request_id='922b6772-0423-4310-9c17-9ad249f6cd72';
```

## Switch-off / rollback

Close the private Edge gate and target SQL channel first. Remove the permit so
the bearer has no authorization value. The absolute expiry and SQL deadline are
additional backstops, not substitutes for closing admission. Preserve the original
private status capability until reconciliation finishes; no status secret may be
published. Existing status must keep working with submission OFF. If an Edge code
rollback is necessary, the compatible v1 handler can serve status with general
submission OFF; do not roll back schemas, drop guards/channel rows, delete the
test or revert the compatible Storefront decoder. An unknown result is reconciled,
never retried as a new order. Do not activate general customer admission.
