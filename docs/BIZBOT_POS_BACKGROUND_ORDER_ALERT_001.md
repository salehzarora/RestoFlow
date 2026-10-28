# BIZBOT-POS-BACKGROUND-ORDER-ALERT-001

Implementation and release handoff. Owner approved implementation/PR only.
No hosted installation, activation, official v64 build or device test is part
of this change. Notification failure must not gate checkout, Inbox polling,
acceptance or printing.

## Background lifecycle repair — local review, not released

`BIZBOT-POS-BACKGROUND-ALERTS-RELIABILITY-001` closes an implementation gap:
the FCM callback previously returned before its posted main-thread handoff
or fallback HTTP read had an Android lifecycle owner. A bounded one-second
handoff now requests the existing eligible FGS before returning. On timeout,
normal-priority delivery, FGS refusal or lost-message notification, a private
API 26+ JobService owns the authenticated full-set read. Empty JobWorkItems
retain arrivals during an older snapshot; normal completion uses atomic
`dequeueWork()` completion, rather than a racing `jobFinished()` call.
Each fallback job invocation has an absolute 25-second budget, including the
existing five-second read floor. No credentials or request data enter job extras.

Existing consent, channel, tenant, generation, revocation and single sound-owner
checks remain. Native delegation still expires with PIN/device authority,
is capped locally at eight hours, and fails after a boot-count change until
foreground authentication binds fresh authority. This repair does not provide
reboot-before-first-launch or expired-PIN coverage. Broader device-scoped
enrollment requires a separately reviewed security/product decision.

The implementation defect is established; attribution of the owner's historical
missed notification remains UNKNOWN. The reported persistent ringing also remains
UNKNOWN for the original incident: independent native 60-second reconciliation existed, with a
20-second read budget. Server dispatch/status metadata alone cannot establish
response application or physical audio stop. Physical start/stop latency and
the foreground/background/process-death/locked-screen matrix are NOT_RUN for
this repair. No v71 rebuild, installation, activation, order, print or ACK is
part of local verification. Historical pilot/application sections below retain
their original scope; this repair adds no restaurant or device activation list.

## Two-device continuity increment — local only, v72 preserved

The preserved v72 QA artifact and seven-file review are unchanged. This successor
source extends that repair; it has not been built into or installed as another APK.
The 2026-10-28 10:50 UTC hosted incident proves one distinct defect: the same
registration received a pending delivery, renewed its generation, then failed
terminal eligibility because the claim query required that older pending delivery
to have the current generation. P20's terminal `sent` row does not prove receipt
or explain its reported approximately 60-second local stop. OnePlus's missed
background arrival also remains unproven physically.

The continuity migration depends on the six already applied observation/ownership
migrations through 20261027142721. Their exact reviewed bytes are included as
source prerequisites, not new production applications. It extends the deployed
post-reconciliation claim function, including its shared writer lock. It uses only
prior pending evidence on the SAME registration and exact organization/restaurant/
branch, requires current effective authority, and creates a terminal row at the
CURRENT generation. Historical ledger rows and retired-owner attribution remain
unchanged; claim/send/finish fences still use current generation/token. A finite
two-minute past-expiry relevance window and deduplication before the bounded
batch prevent historical replay. An FCM cancel is only a refresh signal; the
authenticated full pending set remains authoritative.

The existing single-flight full-set reconciliation runs every 10 seconds only
while its FGS owns a verified, nonempty, still-authorized ringing episode.
There is no idle, per-request or JobService poller. Hints retain the five-second
floor and can request an earlier read. The 20-second absolute read watchdog,
request/authority expiry and 15-minute hard episode remain. Periodic load is at
most six reads/minute during that episode (initial read plus at most 90 periodic
reads); healthy lost-hint stop targets 10 seconds plus response latency. Android
suspension prevents a strict wall-clock guarantee. Empty/invalid/denied/offline
state stops coverage, and resolving A never silences genuinely pending B.

Temporary native diagnostics use only the fixed `BizbotAlertState` tag and a
closed enum/counter serializer: UTC/elapsed time, process-local ordinal, callback
kind/priority, authority/channel classification, FGS/job/status stage, bounded
pending count and MediaPlayer start/stop calls. No payload, customer data, token,
capability, identifier or exception message is accepted by the sink. OS log PID
and process-local ordinal identify native events; a cloud `sent` timestamp alone
never proves their correlation. A stop call is not a claim of physical silence.
These diagnostics add no scheduler, public API, credential access or remote
telemetry. Retire them after the remaining physical unknowns are resolved.

Physical acceptance remains NOT_RUN for the successor. With separately approved
code application/build/update, start bounded read-only captures on both verified
APK/device identities BEFORE naturally occurring legitimate requests. Keep POS
backgrounded until evidence is preserved. Correlate server decision/terminal
ledger, FCM callback kind, authority, FGS/job, full-set application/count and
audio start/stop; owner hearing supplies audibility and start/stop latency.
Compare foreground/background/normal process termination, remote accept and
reject, and a naturally occurring A+B overlap with only A resolved. Separately
record offline/expiry/reboot/Force Stop limits; never create orders, revoke a live
session, change pairing, print, ACK or replay history for this check. Current
v71 lacks these native stages; absence in its logs is UNKNOWN. No DONE claim
until arrival and prompt stop are verified on BOTH real devices.

## HOME identity retarget — PREPARED / NOT APPLIED

`BIZBOT-HOME-ALERT-ALLOWLIST-RETARGET-001` prepares an exclusive notification
replacement from historical HOME `hg`
(`bb80c0d8-6893-4e24-8eea-5a14cf545ecd`) to owner-approved HOME `salehtab`
(`d9f876fb-57e8-44ee-be94-f2284c6fc905`). Both remain scoped to organization
`20605c2b-3145-4803-a990-bbec3d9c1096`, restaurant
`de3bbc64-edad-4ff4-bccd-c2ef217c1d56`, branch
`2847c0be-3e31-45a5-957c-508729f1971e`. Names, a shared branch or physical-tablet
assumptions never authorize registration. The physical mapping is owner testimony
plus backend metadata, without independent tablet UUID inspection or ADB evidence.

The preserved installation supplement reports the existing official POS v65
updated in place on HOME and launching normally. This does not prove FCM delivery,
registration acceptance or physical printing. It does not consume v66 or promote
`currentOfficialRelease`. Historical v64/hg implementation and pilot material
below remains historical; it is not permission to activate that old identity.

Only the notification-specific check in
`app.pos_register_order_alert(uuid,text,text,uuid,uuid,text)` and the validated
`app.pos_order_alert_registrations.pos_order_alert_registrations_check` change.
The public v65 RPC signature/response, auth helper, authority/status/worker,
owner/ACLs, forced RLS, unique indexes, expiry, generation, refresh, arrival cutoff,
leases and delivery idempotency remain unchanged. OLD is removed, not retained as
a fallback. No registration/token/operator revision/history is seeded or rewritten.

**Printing stays separate.** The existing targeted-print rollout still allows
only `bb80c0d8-6893-4e24-8eea-5a14cf545ecd`; ordinary printing remains BLOCKED
revision 1264 with 625 protected historical holds. NEW notification eligibility
does not grant targeted printing or prove that salehtab can print an accepted
order. Pickup rollout 1265 and its order/print contracts are unchanged.

### Separately approved application and recovery

1. Obtain separate PR merge approval, identifying normal Git CI/preview/main
   publication effects. Preparation does not merge, deploy or apply SQL. Before
   pushing/merging, recheck Supabase Git integration: automatic PR branching and
   production database deployment must be disabled. Recheck dedicated Vercel
   project/team/root/main-only production targeting; no production deployment is
   authorized by this preparation.
2. Obtain separate hosted application approval for only
   `20261018182517_bizbot_home_alert_allowlist_retarget_001.sql`. Reconfirm exact
   source and device scopes, the current function/constraint catalog, grants/RLS,
   notification Edge flag false, Vercel flag false, UTC keys absent, platform Cron
   disabled, latest operator OFF (current revision 3), zero registrations and
   deliveries/leases, and no unresolved registration transaction. Inspect metadata
   only; do not invoke registration/auth/claim helpers as read-only probes.
3. The committed migration is atomic. It sets a five-second lock timeout and
   thirty-second statement timeout, then locks settings SHARE before registrations
   ACCESS EXCLUSIVE. It requires operator absent/OFF, empty registration/delivery
   tables, the reviewed old function/security metadata and exact validated CHECK.
   Fresh local/CI replay needs no production fixture rows. It replaces the CHECK
   with an immediately validated NEW-only CHECK and replaces just the function's
   UUID literal. No committed period admits both devices. SQL cannot verify Edge,
   Vercel, physical identity or every client Future; those remain external gates.
4. On timeout, unsafe gate, incompatible history or schema drift, STOP and retain
   evidence. The failed transaction must leave the original function, constraints
   and all rows intact. Never delete, disable, reassign or rewrite rows to force
   application, and never blindly retry an uncertain migration outcome.
5. After a confirmed commit, read migration history (one added version), validated
   CHECK expression, function signature/owner/security/search_path/ACLs, private
   table RLS/denials and zero registration/delivery counts. Compare all unaffected
   auth/printing definitions and business evidence; verify the OLD printing
   allowlist, rollout 1265, BLOCKED 1264 and 625 holds. Keep all notification gates
   OFF. Do not invoke the RPC or dispatch a notification to validate installation.
6. Fresh HOME registration and an attended, at-most-thirty-minute notification
   pilot need another explicit owner authorization. Use existing v65 authentication
   and foreground Enable only then; do not re-pair, reset storage, replay uncertain
   registration or reuse old authority. Follow the scheduler runbook's independent
   gates, exact UTC window and explicit full shutdown; retargeting does not enroll
   HOME, activate Cron or send FCM.

If post-application verification fails, leave notifications OFF and preserve the
successfully installed schema and evidence. Do not edit migration history, run a
destructive down-migration, delete registrations, widen back to both UUIDs or
uninstall/re-pair as recovery. A compensating schema change needs separate review
and approval. Printing authorization is outside this change and outside recovery.

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
in-process cleanup. Visibility expiry does not invalidate an authenticated
status read already in flight for another request. Cancel hints (including
bounded late expiry hints) only
request a coalesced full-set read. Authoritative empty state cancels coverage;
resolving A while B remains updates coverage silently. A failed read stops
local coverage, and an absent terminal hint cannot leave an indefinite notice.
No fallback timer polls the server or repeats sound. State hints share the
existing single-flight read and five-second coalescing boundary.

This fallback is **best effort**, not guaranteed delivery: the private job owns
verification after the callback, but Android may delay, refuse or stop it.
No sound is authorized without a successful read. API 24/25 omit
the no-FGS fallback because they lack platform timeout enforcement after
process death; the regular eligible FGS path is unchanged. Force Stop cannot
be worked around and requires reopening POS. The fallback job processes only
received refresh obligations; it does not add periodic polling or renew
authority. Android may still suppress/throttle channel sound and
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
