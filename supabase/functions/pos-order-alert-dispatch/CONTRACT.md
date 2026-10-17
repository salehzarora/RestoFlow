# BIZBOT-POS-BACKGROUND-ORDER-ALERT-001 — private notification contracts

Default OFF. No hosted scheduler, secret, token, Firebase app, channel, order,
printing permission or production activation is installed by this change.
FCM is only an opaque hint; failed setup/delivery cannot gate existing checkout,
POS polling, acceptance or printing. No existing order writer/trigger is changed.

## Registration (foreground authenticated POS only)

`public.pos_register_order_alert(p_installation_id uuid, p_fcm_token text,
p_status_secret text, p_device_id uuid, p_pin_session_id uuid,
p_device_session_token text)` uses the existing full real paired/PIN authority.
The initial exact allowlist is Maps Burger/HOME only. An operator must enable
`app.set_pos_order_alerts(true, reason, reference)` separately before registration.
All roles including service_role are denied direct table access; only a real
`authenticated` caller may register. No client activation API exists.

Native generates a random 256-bit lowercase-hex status secret, stores it encrypted,
and gives it to Flutter solely for this authenticated registration. Server stores
only its SHA-256. Native never receives the Supabase session, device token, PIN
or service key. Success returns `ok`, `registration_id`, `authority_expires_at`.
Authority is capped at the earliest real PIN deadline, real device-session deadline
and last genuine foreground refresh + eight hours. The separate refreshed_at
clock bounds renewal without moving the original arrival cutoff. Background
status never renews it.

Same installation/token/PIN/device-session/secret/config refresh retains generation
and arrival cutoff. The registration_id is stable for an installation, whereas server generation
changes on rotation. Raw hints never grant authority: native must reconcile using
its CURRENT encrypted secret and captured native generation. Rotation supersedes
old server generation; local logout/unpair must
first durably disable native alerts, then best-effort `/disable`. The existing POS
logout is local, so server PIN expiry alone is not immediate local logout proof.

## Native status / disable gateway

POST `/functions/v1/pos-order-alert-status` with
`Authorization: Bearer <status-secret>` and exactly `{ "installation_id": UUID }`.
No query credentials, Origin/CORS, customer capability or cookie fallback.

Success: `{ok:true, registration_id, server_time, authority_expires_at,
requests:[{request_id,expires_at}]}`. IDs are internal opaque UUIDs; no customer,
phone, notes, items, totals, order IDs, printing data or other tenant scope is
representable. At most 50 actionable, new-live-enrolled requests after the enable
cutoff; overflow fails closed. Native must verify registration identity, capture
its own generation across every await, and clamp each alarm to both deadlines.

The service-only `pos_order_alert_status(uuid,text)` receives SHA-256(secret).
It is STABLE/read-only: no renewal, heartbeat, quota, audit, order or printing write.
It revalidates current scope/device/pairing/session/PIN/employee/membership and role.

POST the same exact credentials/body to `/functions/v1/pos-order-alert-status/disable`
for scoped revocation. This separate mutation remains available while alerts are
OFF or authority has expired. It cannot register or affect orders. Stale secrets
cannot revoke a rotated registration.

## Committed event dispatch

The existing unique append-only `web_order_request_events(received)` row is written
in the same transaction as a genuinely new request. The live-enrollment row is also
atomic. No HTTP is performed inside either transaction and retries never add a new
receipt. The worker consumes only receipts after the registration cutoff joined to
live enrollment. Existing `web_order_decisions` and logical expiry supply cancel
hints only for already-recorded notification deliveries. No historical backfill.

`pos_claim_order_alert_deliveries(integer)` leases at most 20 rows (Edge asks 10),
using SKIP LOCKED, unique registration-generation/request/kind identity, two-minute
leases (longer than the bounded ten-item worker invocation), and a maximum of three sends. `pos_finish_order_alert_delivery` accepts
only the exact lease. Retries wait at least one minute. UNREGISTERED disables only
the original registration generation; an old send cannot disable a rotated token.
These RPCs are service-only, never callable by anon/authenticated clients.

Worker POST `/functions/v1/pos-order-alert-dispatch`, empty JSON `{}`, requires its
own distinct random 256-bit `POS_ORDER_ALERT_WORKER_SECRET` plus
`POS_ORDER_ALERTS_ENABLED=true`. Status requires the same default-OFF environment
gate. The worker needs `SUPABASE_URL`/`SUPABASE_SERVICE_ROLE_KEY` server-side and
`POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT`, a securely installed JSON service-account
credential. Never put credentials or tokens in Git, URLs, app bundles or chat.
Both gateway handlers deliberately use verify_jwt=false and authenticate their own
separate, constrained secrets. The existing media publisher keeps verify_jwt=true.

FCM HTTP v1 uses a short-lived scoped OAuth assertion from server credentials.
The Android data payload is exactly `version='1'`, `kind='pending'|'cancel'`,
`request_id`, `expires_at`, `registration_id`; high priority, TTL <=120 seconds and
<= request/authority deadline (cancel hints have <=60 seconds). It contains no
notification customer text or credentials. Repeated local sound is Android-owned,
not repeated FCM. Unknown send results may duplicate hints; native reconciliation
and deduplication make that harmless. FCM acceptance is not device/paper delivery.

## Later owner-authorized setup / OFF

1. Register the production Android app/package in an owner-controlled Firebase
   project and enable FCM HTTP v1. Private service-account credentials are installed
   directly in the supported Supabase Edge secret store, never supplied in chat.
2. Review/apply this exact additive migration, deploy the two existing source
   gateways, keep environment and database gates OFF. Preserve existing checkout,
   BLOCKED policy and historical holds.
3. Separately configure one bounded `pg_cron`/`pg_net` call to the private worker;
   use Supabase Vault for its worker bearer, never inline credentials in the job.
   No scheduler/extensions/grants are created by this migration. Choose a bounded
   interval; calls only dispatch new events/cancellations, never periodic chimes.
4. Install compatible Android under separate authorization. Enable only HOME,
   obtain notification permission and perform the owner's physical checklist.

OFF: operator calls `app.set_pos_order_alerts(false, reason, reference)` and sets
`POS_ORDER_ALERTS_ENABLED=false`; disable the separately installed worker schedule.
Native observes revoked authority on its next bounded status check and hard expiry
always applies offline. Already delivered FCM cannot be recalled; it confers no
permission. Preserve existing orders, receipt/decision/delivery evidence and all
historical print holds. No printer/queue reset, ACK or resend is a rollback.

Official references checked for this implementation:
- https://firebase.google.com/docs/cloud-messaging/send/v1-api
- https://supabase.com/docs/guides/functions/schedule-functions
