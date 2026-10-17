# BIZBOT-POS-BACKGROUND-ORDER-ALERT-001

Implementation and release handoff. Owner approved implementation/PR only.
No hosted installation, activation, official v64 build or device test is part
of this change. Notification failure must not gate checkout, Inbox polling,
acceptance or printing.

## Android feasibility decision

The current private Android distribution targets SDK 36 (minimum 24). A
visible, user-stoppable `specialUse` foreground service is used solely for a
time-limited, authenticated pending Pickup reminder. It does not perform
order processing, printing, idle monitoring, media playback or messaging
continuity. This is an engineering assessment of the documented residual
service category, not Google Play approval. A future Play release requires
its own declaration, justification and review. Reassess before target 37.

The notification service has one local approximately ten-second cadence and
one bounded audio clip. It ends on confirmed empty/terminal state, authority
loss, local expiry, notification disable or operator Stop. A background
episode is capped at fifteen minutes. Requests and delegated authority have
independent expiry bounds; neither can be renewed by the native status API.

High-priority FCM is an OS background-start exemption only when actually
delivered at high priority. Start denial/downgrade requests a best-effort
authenticated full-set status read. On API 26+, a verified pending set can
produce one generic audible notification through the actual Android channel,
not a repeat service. A durable, bounded heard-request fence is committed to
the existing encrypted vault before notification delivery, including uncertain
delivery outcomes. Duplicate/delayed hints and process recreation cannot
authorize another sound for those still-live IDs. The shared playback cadence
also fences foreground/FGS/fallback handoff; the FGS notification stays silent.
Notification denial/muting,
silent/vibrate, DND, deep Doze, Force Stop, OEM battery killing and missing
Google Play services can prevent sound/delivery. No volume/DND overrides,
full-screen intent, exact alarm, boot service or battery-exemption request.
Normal process termination and Android Force Stop are different: Force Stop
requires the operator to reopen POS. A bounded partial wake lock does not
guarantee a ten-second cadence in deep Doze.

Fallback visibility is capped at 60 seconds and by the earliest verified
request/authority deadline using Android's platform notification timeout plus
in-process cleanup. Cancel hints (including bounded late expiry hints) only
request a coalesced full-set read. Authoritative empty state cancels coverage;
resolving A while B remains updates coverage silently. A failed read stops
local coverage, and an absent terminal hint cannot leave an indefinite notice.
No fallback timer polls the server or repeats sound. State hints share the
existing single-flight read and five-second coalescing boundary.

This fallback is **best effort**, not guaranteed delivery: Android may kill
the process after `onMessageReceived` returns before asynchronous verification
finishes. No sound is authorized without a successful read. API 24/25 omit
the no-FGS fallback because they lack platform timeout enforcement after
process death; the regular eligible FGS path is unchanged. Force Stop cannot
be worked around and requires reopening POS. A future lifecycle-managed
fallback job would require separate scope; no such job or additional polling
is introduced here. Android may still suppress/throttle channel sound and
heads-up presentation even when the app requests them.

Primary references: [service types](https://developer.android.com/develop/background-work/services/fgs/service-types),
[background-start restrictions](https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start),
[notification permission](https://developer.android.com/develop/ui/views/notifications/notification-permission),
[Doze](https://developer.android.com/training/monitoring-device-state/doze-standby),
[FCM priority](https://firebase.google.com/docs/cloud-messaging/android-message-priority),
[FCM processing lifetime](https://firebase.google.com/docs/cloud-messaging/android/receive-messages),
[notification silence and timeout](https://developer.android.com/reference/androidx/core/app/NotificationCompat.Builder),
[Play declaration](https://support.google.com/googleplay/android-developer/answer/13392821).

## Authority and event path

1. Foreground authenticated POS registers its installation/FCM token using
   the existing real paired-device/PIN proof. Server derives all scope.
   The initial pilot admits only Maps Burger HOME
   `bb80c0d8-6893-4e24-8eea-5a14cf545ecd`.
2. Native generates a separate 256-bit status secret, protected by its own
   Android Keystore AES-GCM vault. It never receives the pairing token,
   staff PIN, Supabase session or customer status capability. Local logout,
   identity/security changes and deliberate OFF clear native authority;
   revocation is also sent best-effort. Token rotation requires real
   foreground registration again.
3. Registration is bounded by the actual PIN/device-session expiry and an
   eight-hour maximum. Foreground discovery may refresh it through real
   authentication; the native service cannot extend it. Read-only status
   rechecks active scope/device/pairing/PIN/employee/membership each time.
4. Existing append-only `web_order_request_events(received)` and
   `web_order_decisions` are already recorded transactionally. A new private
   delivery ledger consumes only committed, newly live-enrolled requests
   after the registration/enable cutoff. No order trigger rewrite, external
   call inside the order transaction or historical notification backfill.
5. The server-only dispatcher sends bounded-retry FCM HTTP v1 hints, with
   `version`, `kind`, opaque `request_id`, `registration_id`, and expiry.
   No customer details, prices, payment data or credentials. Unknown sends
   may duplicate hints; only reconciliation authorizes repeats. Logical
   expiry creates no new order/decision mutation.
6. The native status endpoint returns only server time, registration identity,
   authority deadline and pending UUID/deadline pairs. It is non-renewing and
   read-only. Separate `/disable` can revoke only that installation.
7. A single native sound owner shares cadence with the retained foreground
   Inbox audio transport. Background hints reconcile; foreground hints use
   the existing single-flight Inbox refresh. Background reads run on state
   hints and at most the documented slower cadence, never every ten seconds.
   Notification tap queues Inbox opening behind normal pairing/PIN gates.
   There are no lockscreen decisions or printing actions.

Private notification tables use forced RLS and no direct application-role
access. Operator settings are append-only and absent by default. Worker/status
RPCs are service-only; registration alone uses the authenticated POS proof.
No pricing, acceptance, print authorization, SQLite or spool schema changes.

## Separately authorized installation and enablement

Firebase is currently unconfigured on this workstation. Owner-side setup:

1. Choose/create the intended Firebase project and Android app
   `com.restoflow.pos`; obtain its **public** app ID, API key, project ID and
   sender ID. Confirm the HOME hardware has compatible Google Play services.
   No private service-account key belongs in chat, Git or an APK.
2. Store a dedicated FCM sender service account using the supported Supabase
   Edge secret store as `POS_ORDER_ALERT_FCM_SERVICE_ACCOUNT`; grant only the
   necessary FCM send privilege. Store a separate random
   `POS_ORDER_ALERT_WORKER_SECRET` server-side. Keep
   `POS_ORDER_ALERTS_ENABLED` absent/false initially.
3. After review/merge and separate authorization, apply only the new alert
   migration, deploy `pos-order-alert-status` and `pos-order-alert-dispatch`
   with their explicit gateway authorization (JWT gateway verification OFF).
   Existing functions and their JWT settings are unchanged.
4. Separately configure a bounded scheduler invocation (for example
   Supabase `pg_cron`/`pg_net`) with worker authorization held in Vault.
   Use a short supported cadence for receipt/terminal hints; do not enqueue
   ten-second FCM repeats. No scheduler or Vault secret is installed by this
   migration. Keep endpoint access private to the worker secret.
5. A future separately approved Android build supplies both opt-ins:
   Dart define `BIZBOT_BACKGROUND_ORDER_ALERTS=true` and Gradle property of
   the same name. Public Gradle properties:
   `BIZBOT_FIREBASE_APP_ID`, `BIZBOT_FIREBASE_API_KEY`,
   `BIZBOT_FIREBASE_PROJECT_ID`, `BIZBOT_FIREBASE_SENDER_ID`.
   Backend is bound to the existing `RESTOFLOW_SUPABASE_URL` build input.
   No Google Services plugin/JSON or service account is embedded.
6. Under explicit HOME pilot authorization, enable the private operator
   notification setting and Edge flag, then enable alerts inside the
   authenticated Inbox. The explanation precedes POST_NOTIFICATIONS.
   Missing configuration/denied permission fails silent and existing Inbox
   polling continues.

## OFF, diagnosis and rollback

Local Inbox OFF or notification Stop destroys this separate delegated
authority and stops its service/audio without changing POS pairing/storage.
Server kill switch: append notification setting OFF and set
`POS_ORDER_ALERTS_ENABLED=false`; disable the notification scheduler. New
registration/status/delivery then fail closed, and local request/hard expiry
still bounds offline ringing. Notification rollback never changes checkout
admission or print policies and never recreates/resends an order.

Troubleshoot configuration presence, permission/channel settings, public
Firebase project/app match, current real PIN/device authority, registration
expiry, worker lease state, FCM token-invalid classification and OEM battery
policy. Do not log tokens/capabilities, inspect customer payloads, fabricate
readiness, relax RLS or reset POS data. A notification fallback is not repeat
service PASS.

## Deferred HOME v64 physical acceptance

After separate release/install/hosted authorization, test one independently
approved bounded request while preserving the current print protections.
Verify foreground, background, locked screen, normal process termination and
resume with one sound cadence; multiple requests must not create parallel
loops. Verify permission denied/channel muted/silent/DND, delayed/duplicate/
downgraded FCM, offline hard expiry, logout/unpair/OFF and Force Stop behavior.
Record Android version, Play services and Xiaomi/Redmi battery settings.
Observe actual audio and notification privacy/tap-to-PIN behavior; automated
state tests and successful Android compilation do not prove physical delivery.
No Accept or printing is necessary for initial notification acceptance.
