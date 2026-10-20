# Platform online orders — Issue #353

Status: implementation and isolated verification; **not a production readiness claim**.
This is one platform installation, not a procedure repeated for each restaurant.
The historical Maps Burger/HOME pilot documents remain audit records, not the
onboarding authority for new restaurants or devices.

## Authority and onboarding

Organization remains the tenant. Every scope is organization + restaurant +
branch, established by server relationships rather than a slug or device list.
Branch creation provisions online-order settings and notification scheduling
state, allowing authenticated POS registration before publication. Publishing a
storefront provisions its submission channel.
New settings permit Pickup, alerts and exact new-web-order printing by default.
Existing intentionally disabled channels are preserved. A published menu, active
organization/restaurant/branch, Pickup enabled, unpaused service and OPEN hours
are still required. Delivery and online payment are not introduced here.

The website consumes `storefront_menu.service.ordering_enabled` for every slug.
It never activates a channel or supplies a tenant/price/authorization override.
Normal submissions use service-only `submit_web_order_platform_request`, retaining
canonical pricing, trusted preparation snapshots, limits, capability recovery and
client-request idempotency. Private legacy test/pilot RPCs and existing receipt
lookups remain compatible. Only genuinely new committed requests receive platform
enrollment; no migration backfills previous requests, dispatches or attempts.

A newly paired POS joins its branch Inbox through existing active pairing,
device session, genuine employee PIN, membership and branch authorization. It
does not need a deployment, UUID allowlist or manually issued backend permission.
Other tenants cannot see or decide its requests. Normal manager controls remain
the way to publish, configure Pickup, hours and temporary pause. The scoped
`get_online_order_settings` / `set_online_order_settings` authenticated APIs
add persistent branch intake, targeted-print and alert switches with audit events.
They are not anonymous APIs and cannot change a different tenant.

## One decision and one physical-send authority

All eligible branch POS devices see the same pending Inbox. The existing locked
decision transaction and unique decision/canonical mapping choose one winner.
Only its accepting POS receives the exact initial-print lease. KDS workflows use
the existing KDS route instead; this change does not broadcast a kitchen job.
Printers, destinations and kitchen workflow remain configured through the
existing per-device/branch settings. Missing, offline or ambiguous printer
configuration preserves the accepted order and fails closed; it never authorizes
a fallback send or a second acceptance.

The base ordinary-print containment policy remains authoritative. The new
`web_order_printing_enabled` bit permits only the exact `web-initial:<request>`
callback after a fresh, authenticated containment read. It is not ordinary drain,
historical ACK or reprint permission. Server claim/begin still require the exact
enrollment, accepting device/session/PIN, canonical decision, current branch
generation, unchanged containment revision, genuine fresh secure-spool/printer
readiness and absence of a historical hold. The first irreversible begin remains
the one physical-send reservation. Language, preparation counts, BLE, SQLite,
encryption keys, renderer and manual reprints are unchanged.

The compatibility target-only projection supports existing installed POS for its
latest accepting lease. It is at-most-once safe, but v65 can accept a second
request while the first print callback is delayed; its latest-lease-only adapter
can then deny the first callback without paper. This is a deployment gate, not
a reason to retry an accepted order. The updated POS handles distinct concurrent
exact callbacks without replacing one request's authority with another's. A later
explicit BLOCKED revision or branch print-disable invalidates platform leases.
It does not revive prior leases when printing is later re-enabled.

## Continuous notification coverage

`POS_ORDER_ALERTS_ENABLED` is still the global emergency switch. The instant wake
has its separate explicit enable flag; Vercel has its independent authenticated
Cron enable flag. Missing/non-true master flags remain OFF. With the platform
installed and enabled once, normal mode is continuous without UTC timestamps.
`POS_ORDER_ALERT_MODE=pilot` explicitly retains the optional strict maximum
30-minute UTC window in both Edge and Cron. Invalid mode denies dispatch. No
per-restaurant environment variables, credentials or deployments are needed.

A committed NEW pending submission schedules one best-effort `waitUntil` wake.
Replays, status reads, rejected/failed/uncertain submissions and private test/pilot
routes do not. A wake carries `{}` and the private worker bearer only. Checkout
responses never await notification transport. Cron remains the once-per-minute
fallback for lost wakes, transient retries, terminal and expired notifications.
All callers share database delivery uniqueness, fair bounded branch scheduling,
max-ten claiming, lease ownership, existing retry limits and the FCM sender.
FCM is an untrusted opaque hint, never authority to Accept or print.

Each device still needs Android permission, usable Google Play services and its
normal Inbox notification consent once. Foreground renewal requires current real
PIN authority; it cannot extend an expired employee session. Native token rotation
uses the status-only capability at `/pos-order-alert-status/token/refresh`, updates
the current token and delivery generation to fence old-token outcomes, and never
extends its existing authority. Reauthentication
remains necessary when employee/device authority expires. Uncertain registration
is reconciled; provider reset, pairing reset and clearing data are not recovery.
Force Stop, denied permission, muted channel, DND, OEM battery restrictions and
network outages prevent an absolute delivery guarantee. Foreground Inbox remains
authoritative and cancellation reconciles the complete pending set.
Every genuine foreground registration rotates the routing generation, including
same-token renewals. Native refresh compares the captured generation atomically;
an older background request cannot overwrite that fresh binding. Native
preparation/bind/clear also fence delayed success/denial completions across pause.
Background token updates are serialized and coalesce to the latest SDK token.
A lost or unverified update response blocks further background token writes,
including after process recreation, until normal authenticated foreground
reconciliation. This prevents stale-generation retries; it can interrupt
background coverage and must not be bypassed by resetting providers or data.

## Installation and rollback gates

1. Require independent SQL/RLS/security review and full exact-head CI. Recheck
   source, deployed Edge versions, current tenant settings, and protected print
   evidence. Preserve all audit registrations/deliveries, including completed
   pilots. Existing live website ordering must remain available.
2. Keep notification master/operator/Cron OFF during the cutover. Apply only
   `20261020143657_bizbot_platform_online_orders_353.sql` by the approved versioned
   migration process. Independently verify schema AND history before retrying an
   uncertain outcome. Never repair history or replay a COMMIT automatically.
3. Deploy the reviewed status and dispatcher functions and dedicated scheduler
   with notifications OFF. Verify exact source and default-OFF responses. Keep
   the current submission function using its legacy normal RPC and retain the
   current Storefront until the accepting-client gate below is satisfied.
4. Build/install updated POS through the separate official signed release
   pipeline when approved. Every active web-order accepting POS in printer-only
   branches must use the updated exact-callback runtime; alternatively the owner
   must keep older acceptors stopped. Verify this before switching normal
   submissions. Do not overwrite prior APKs, reset pairing, clear local data or
   replay accepted orders. Legacy receipt compatibility remains required.
5. Only after that gate, deploy web-order-submit switching normal submissions to
   the platform RPC, then the Storefront through its normal project. Verify exact
   deployed source, live checkout compatibility and fixed backend/authentication
   boundaries. This is one platform cutover; new restaurants/devices thereafter
   onboard normally without per-tenant deployment or backend activation.
6. With operating authority confirmed, enable shared notification infrastructure
   once, then normal device consent/registration. Do not require per-restaurant
   SQL, secrets, allowlists or deployments. Verify a second tenant and a newly
   paired third device without backend changes.
7. Complete attended end-to-end acceptance before declaring platform readiness:
   tenant A with A1/A2, tenant B with B1; website submission, authorized Inbox and
   background alerts, one competing Accept winner and one configured physical
   ticket, B isolation, new A3 onboarding, revoked A2, expiry/retry, offline printer
   and protected historical records. Mock transport is not physical paper proof.
   Production test orders/device actions need an agreed owner-operated test window.

Emergency shutdown: turn Supabase notification master OFF first, append operator
OFF, disable scheduler forwarding and platform Cron, then stop native coverage.
Branch intake/Pickup pause and branch targeted-print disable are separate
controls; notification failure must not close checkout or alter printing. Keep
accepted orders, attempts, immutable holds and receipts. Reconcile uncertain sends
without automatic resend. Do not delete evidence or reverse successful DDL as an
improvised rollback. Cold-offline imported-spool deferral is unchanged and is not
approved for commercial rollout by this feature.

## Verification record

Record actual local, Linux CI, deployment and physical results separately in the
PR. Local browser fixtures do not prove FCM delivery; Kotlin compilation does not
prove Android background behavior; a successful transport does not prove paper.
The implementation does not consume an Android release version or claim that the
currently installed APK contains these new client changes.
