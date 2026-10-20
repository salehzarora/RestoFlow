# Notification scheduler activation handoff

## Platform operation — Issue #353

The [platform contract](../../docs/BIZBOT_PLATFORM_ONLINE_ORDERS_353.md) supersedes
the HOME-only setup below for new onboarding. Once the reviewed platform has been
installed and enabled, continuous mode does not require UTC timestamps or a
restaurant/device allowlist. Global emergency OFF, production-only independent
authentication, exact dispatcher destination and database delivery authority
remain mandatory. `POS_ORDER_ALERT_MODE=pilot` explicitly retains the historical
maximum-30-minute UTC controls; malformed modes fail closed. The once-per-minute
schedule is shared infrastructure, not a new restaurant setup step. Historical
statements below describe their captured dates and are not current live state.

Deploy only after the new database RPCs exist. Keep notification controls OFF
during installation, verify actual deployed source/configuration, and complete
the multi-tenant acceptance matrix before claiming platform readiness. Disabling
Cron alone does not revoke Edge/native authority; use the emergency shutdown in
the platform contract. No credential rotation or new project is required.

## Current HOME identity handoff — PREPARED / NOT APPLIED

`BIZBOT-HOME-ALERT-ALLOWLIST-RETARGET-001` proposes replacing notification HOME
`hg` (`bb80c0d8-6893-4e24-8eea-5a14cf545ecd`) exclusively with owner-approved
`salehtab` (`d9f876fb-57e8-44ee-be94-f2284c6fc905`) in the unchanged Maps Burger
tenant. The existing v65 update/physical mapping is owner-reported, not ADB or
FCM acceptance evidence. Hosted notification eligibility is still OLD-only.
Printing authorization remains OLD-only and is not retargeted by this change.

Follow the [notification-only migration/application gates](../../docs/BIZBOT_POS_BACKGROUND_ORDER_ALERT_001.md#home-identity-retarget--prepared--not-applied)
before any later registration or pilot. Separate approvals are required for PR
merge and its Git automation, migration application while all notification gates
are OFF, and fresh HOME registration/attended pilot. Do not enable HOME using the
historical identity/runbook below. After approved application, catalog verification
must prove the RPC and validated CHECK both pin NEW, with no OLD fallback.

Current read-only preparation baseline: both notification flags false, UTC keys
absent, operator OFF revision 3, zero registrations/deliveries/leases; platform
Cron disabled with one `/api/dispatch` once-per-minute definition. Rollout 1265,
ordinary printing BLOCKED 1264 and 625 immutable holds remain unchanged. No
scheduler executable/configuration, credential, Edge Function, APK or gate changes
belong to this PR. The existing UTC/explicit-shutdown procedure still applies.
Retargeting does not register a token, turn on Cron, send FCM or authorize printing.
Uncertain registration needs reconciliation, not reset/replay. Preserve evidence;
no destructive rollback, row deletion, uninstall/re-pair or two-device fallback.

## Historical Cron schedule preparation record

Work ID: BIZBOT-HOME-FCM-CRON-SCHEDULE-001. This PR prepares exactly one
`/api/dispatch` schedule, `* * * * *`, in the dedicated scheduler's `vercel.json`.
It is preparation only: no hosted schedule or setting is changed by opening it.
**Merging may trigger a Git-integrated Production deployment that registers the
schedule. Disable and verify the platform Cron switch BEFORE any later merge or
production deployment. If the switch is enabled or unknown, STOP before merge.**

Keep `POS_ALERT_CRON_ENABLED=false`, Supabase `POS_ORDER_ALERTS_ENABLED=false`,
operator alerts absent/OFF and both pilot UTC timestamps unset until separate
owner authorization. An enabled Cron can create billable function invocations
even when the handler rejects forwarding. A 30-minute window limits forwarding;
it does not disable Cron or all server/native notification authority. A later
pilot requires exact approved UTC start/end, an available shutdown operator and
explicit confirmation that server gates, Cron and native coverage are stopped.

Read-only schedule preflight on 2026-10-18 (23:48 UTC on 2026-10-17): main
`e004d807811b036b3265088bda6faacc4cc239c2`, CI `39078357292` SUCCESS. Dedicated
Production `dpl_HQk5AN1gYbeDiLcbtDqNLuS4jDmj` is READY from that exact source with
the UTC guard. The correct owner team is Pro; one-minute Cron is eligible.
**The current platform Cron switch is enabled, with zero definitions.** It has
not been disabled by this task. Both notification flags are false, UTC values
unset, operator settings/registrations/deliveries zero, and secret metadata
present without retrieving values. HOME restrictions, rollout 1265, BLOCKED 1264
and all 625 holds are unchanged. Recheck these gates before any later mutation.

## HOME pilot preparation — BIZBOT-HOME-FCM-PILOT-PREP-001

The OFF-only installation is already complete. Reuse the existing Firebase sender,
worker credential and independent inbound bearer unchanged; the rotation section
below is recovery guidance requiring separate approval, not a pilot step.

Exact scope:

- Dedicated Vercel project `prj_QVlsRLCT0IsnqHwhMoPzNq6D3Vos`, team
  `team_yynO6ARGc6VsRrAB69hOTTZy`, root `services/pos-alert-cron`, Node 24.
- Supabase `oqmevrndtivqxgyvcmwy`, Firebase `bizbot-production`.
- HOME POS `hg`, device `bb80c0d8-6893-4e24-8eea-5a14cf545ecd`, organization
  `20605c2b-3145-4803-a990-bbec3d9c1096`, Maps Burger restaurant
  `de3bbc64-edad-4ff4-bccd-c2ef217c1d56`, branch
  `2847c0be-3e31-45a5-957c-508729f1971e`.
- POS v64 installation/launch/kitchen printing are owner-reported, not a new ADB
  or notification acceptance claim. No APK or device action belongs to this PR.

Read-only preflight on 2026-10-18: approved main
`0daced0c4dd956f5addaacb3a3813cb4436c288e` and CI `39073448483` SUCCESS;
dedicated production deployment `dpl_94xyLB62jtFrnv28kRBCNnWhwMUP` READY from that
SHA. Its Cron definitions are empty; the platform Cron toggle is enabled but has
nothing scheduled. Both server notification flags are false, and settings,
registrations and deliveries are zero. Both alert Edge routes are ACTIVE v2 with
`verify_jwt=false` and independent application authentication; OFF probes return
`503 disabled`. There are 166 migrations. Maps Burger rollout 1265, printing
BLOCKED 1264 and all 625 immutable holds are unchanged.

Existing non-sensitive installation receipts record that the same in-memory worker
was successfully written/verified in both platforms. Current secret-name/storage
metadata agrees with the installed production-only Vercel secret identities.
This is historical provisioning evidence plus current metadata, not a fresh
secret-value equality comparison. Never retrieve values to compare them, rotate
them for this pilot, or infer equality from secret-name presence alone. Any
credential drift or authenticated dispatcher failure is a STOP for separately
authorized secure reconciliation, not a reason to replay an invocation.

### Enforced window and its limits

Supply absolute, owner-approved `POS_ALERT_PILOT_START_UTC` and
`POS_ALERT_PILOT_END_UTC` as server-only Production Config values. Accept only
`YYYY-MM-DDTHH:mm:ssZ` or `YYYY-MM-DDTHH:mm:ss.sssZ`, with real calendar dates,
start before end and duration **at most 30 minutes**. No local-time strings,
offsets, whitespace or relative/rolling dates. There are no source defaults.
The endpoint forwards only for `start <= server UTC now < end`, in production,
with its existing authentication/configuration guards. The HTTP wait is also
bounded by the cutoff. Missing/invalid/expired configuration is fail-closed.

**The cutoff automatically stops new scheduler forwarding, not every downstream
effect.** A worker or FCM message already in flight can finish; cancellation of
the HTTP caller does not undo it. The native status capability can last up to
eight hours, bounded by genuine PIN/device expiry, and background episodes have
their existing 15-minute bound. The window does not automatically clear the Edge
flag, append an operator OFF revision, disable Cron, or cancel native audio.
An operator must be available at cutoff to perform and verify shutdown below.
If unattended expiry of all server/native authority is required, STOP before
activation: that needs a separately approved contract change, not this scheduler
preparation. A clock/configuration/deployment problem is also a STOP.

### Later, separately authorized activation

1. Reconfirm HOME is the intended official v64 installation. The owner checks
   Android notification permission, the app's notification channel/volume/DND,
   working Google Play services and battery/background restrictions. Record actual
   OS/OEM settings; do not promise Force Stop, deep Doze or denied-permission
   delivery. Do not change pairing, PIN, printer settings, outbox or spool.
2. Verify Supabase `POS_ORDER_ALERTS_ENABLED=false`, Vercel
   `POS_ALERT_CRON_ENABLED=false`, operator setting absent/OFF and no enabled
   registration. Preserve rollout 1265, BLOCKED 1264, all 625 holds and HOME's
   existing targeted printing. Stop on scope/authority/credential drift.
3. Before any separately approved merge/Production deployment of the prepared
   schedule, disable the exact project's platform Cron switch and verify its
   disabled state through current platform metadata. Keep both notification flags
   false, operator alerts OFF and UTC values unset. The UTC guard is already
   installed. Do not merge or deploy if switch state, source CI or other gates are
   unverified; an enabled switch can begin billable ticks immediately on deployment.
4. After separate merge/deployment approval, install only the reviewed schedule
   below in the dedicated project while the switch remains disabled. Verify actual
   Production source/alias, exact configuration, one definition and disabled state.
   Protection must admit legitimate Vercel-authenticated Cron without weakening
   access controls or exposing the bearer. Missing/invalid auth, Preview, OFF and
   out-of-window calls must never forward. Do not copy the entry into another
   project's config. No UTC or notification activation is authorized by this PR.
5. Only under separate owner pilot authorization, establish exact UTC start/end
   of at most 30 minutes while a shutdown operator is available. Configure the two
   server-only Production UTC values; env updates require a new deployment, so
   choose a window that will not expire during installation. Never extend it
   silently or reuse an old activation deployment as a fresh window. Within it,
   enable the existing Supabase notification flag and append the operator setting
   through privileged `app.set_pos_order_alerts(true, reason, operator_reference)`.
   The operator records the reason/reference and returned revision; do not alter
   private tables directly. Set the Vercel flag true and deploy its reviewed
   production env snapshot. Do not create/rotate/read credentials or change any
   order/printing gate. Keep Cron disabled until HOME registration is verified.
6. The owner uses HOME's existing foreground, authenticated POS Inbox switch to
   opt in/register, with the real paired device and active PIN/shift. Do not
   manufacture registration proof or insert a token. The registration RPC and
   table CHECK both pin the exact HOME/org/restaurant/branch above. Read-only
   verification must show only HOME enabled; never widen this allowlist. New
   enable revisions require fresh foreground registration and do not backfill
   requests from before the setting/registration cutoff. Then enable only the
   dedicated project's Cron switch under the same bounded approval.
7. Observe a **naturally arriving legitimate Pickup request** created after those
   cutoffs. Do not create a real/synthetic test order, invoke dispatch manually,
   Accept/Reject, pay, claim, reprint or send printer bytes to validate alerts.
   Controlled orders require separate authorization. Observe ordinary business
   resolution without changing its checkout, acceptance or targeted-print flow.
8. Record opaque request/registration/delivery identities and UTC timestamps only:
   pending creation, first scheduled worker result, owner-observed notification/
   audio receipt, foreground/background/screen-off state, and naturally occurring
   accepted/rejected/expired resolution followed by cancellation. Compare server
   evidence with actual device observations; FCM transport success is not proof
   of display/audio. Missing arrivals or unobserved resolution make that portion
   INCONCLUSIVE, never PASS. Duplicate/overlapping ticks rely on existing database
   leases/idempotency, not a new local lock or repeated manual sends.
9. At the cutoff (or earlier on a failure), execute the shutdown below immediately.
   The endpoint automatically denies new forwarding at/after END even if its
   deployed flag remains true. Verify server gates and Cron are actually disabled,
   and the owner confirms HOME audio/notification stops. Do not infer global
   shutdown solely from the UTC guard, HTTP 200, or an empty pending count.

Read-only operator acceptance queries (no token/status-secret/customer fields):

```sql
select revision, enabled from app.pos_order_alert_settings order by revision desc limit 1;
select device_id, organization_id, restaurant_id, branch_id, enabled, count(*)
from app.pos_order_alert_registrations
group by device_id, organization_id, restaurant_id, branch_id, enabled;
select state, count(*) from app.pos_order_alert_deliveries group by state;
```

Use the authorized operator connection, not an app-role workaround. Retain audit
rows and leases. Zero rows is the current OFF baseline, not a future requirement
to delete evidence after the pilot. Inspect claims/sends/uncertain outcomes before
any later activation; never automatically replay a timed-out notification.

## Secure worker rotation — separate approval required

The old Supabase worker bearer was not retained. Do not retrieve it or copy it
through a console. A later scoped installation must rotate it into both stores
using the previously verified local in-memory HTTPS provisioning approach:

1. Reconfirm exact Supabase project `oqmevrndtivqxgyvcmwy` and the newly approved
   dedicated Vercel project/team IDs. Keep Supabase `POS_ORDER_ALERTS_ENABLED=false`,
   Vercel `POS_ALERT_CRON_ENABLED=false`, and no Cron schedule throughout rotation.
2. Use a controlled local C# process with authenticated HTTPS clients, strict
   certificate validation, redirects disabled, diagnostics/tracing/transcripts
   disabled, generic error handling and no credential-bearing output or files.
   Authenticate from the approved secure local credential stores directly in
   memory. Verify this path for **both** APIs before generating anything; no
   credentials in MCP/tool inputs/results, command arguments/history, telemetry,
   environment dumps, temporary files, SQL literals/parameters or repository.
3. Generate two independent cryptographically random 32-byte values in process
   memory, encode as lowercase hex, and check they differ. Install the new worker
   value through `POST https://api.supabase.com/v1/projects/oqmevrndtivqxgyvcmwy/secrets`
   in the HTTPS JSON body. Preserve the FCM service account unchanged and the
   Supabase OFF flag. No SQL, Vault or Google key operation is needed.
4. Send that same worker value and the independent inbound `CRON_SECRET` only in
   HTTPS bodies to the Vercel environment API for the exact new project/team.
   Require write-only Sensitive/Secret storage and Production-only targets. The
   process must suppress API responses which may echo values, and retain only
   names, IDs, timestamps, storage type and target metadata.
5. Cross-service rotation is not atomic. On any error or uncertain outcome,
   leave both flags OFF and Cron absent/disabled. Reconcile name/type/target
   metadata first; never restore the unknown old bearer or assume rollback.
   A fresh coordinated rotation needs explicit reconciliation/authorization.
6. Verify secret names and metadata only. Deploy the reviewed source with the
   new production env snapshot while still OFF. Vercel env changes require a new
   deployment to reach runtime. Do not use env pull to export production secrets.
   Dispose/clear in-memory buffers; retain no bearer or private key in evidence.

Metadata proves presence and scope, not equal secret values. The provisioning
process must validate both successful authenticated writes of the same in-memory
worker value; do not claim a metadata-only equality check. If transport or error
suppression cannot be proven safe, stop before generating or rotating secrets.

## Default-OFF schedule installation acceptance

- Confirm exact reviewed source, dedicated project/root and production deployment
  identity/alias. No existing product project or custom-domain changes.
- Verify exactly the one approved schedule in source and hosted metadata, with
  the platform switch disabled; both notification flags false, operator OFF and
  both UTC variables unset. Preserve zero enabled registrations and no deliveries.
- Missing/wrong inbound auth must not forward. With valid inbound auth and OFF,
  expect `503 disabled`; Preview must never forward even if accidentally enabled.
- Verify secret storage type/Production scope and no credentials in logs/bundles.
- Existing alert tables/queue metadata must show no scheduler claims or sends.
  Do not seed registrations, create orders or turn on FCM to verify OFF behavior.
- Preserve Maps Burger rollout 1265, printing BLOCKED revision 1264, all 625 holds,
  previous order/print evidence, official APKs and other devices.

## Prepared schedule — separate merge/deployment approval required

The candidate config contains exactly this schedule, solely for the dedicated
project. Production registration requires later owner merge/deployment approval
and verified platform Cron shutdown beforehand:

```json
{
  "crons": [{ "path": "/api/dispatch", "schedule": "* * * * *" }]
}
```

The schedule is not registered by this preparation. A later merge may automatically
deploy/register it, so the disabled platform switch is a mandatory pre-merge gate.
Follow the HOME-only activation procedure and mandatory UTC window above before
enabling either flag. Preserve the
existing device-authorized registration/status contract; Cron is not a device or
PIN credential. No broad fleet activation is implied.

Install the reviewed schedule while both flags remain OFF, verify platform
authorization/protection behavior, and only then activate the bounded scope under
separate owner approval. A manual request with valid bearer can also invoke this
endpoint when enabled: it is not an exclusive proof of Vercel origin. Protect the
bearer; never use User-Agent, Origin or a query token as authentication.

## Emergency shutdown / rollback

1. **First set Supabase `POS_ORDER_ALERTS_ENABLED=false`** using the authorized
   secure secret path. Verify dispatcher/status OFF responses. This stops new
   invocations before queue claiming; a worker already in flight may finish its
   current batch. Disabling does not recall a delivered notification.
2. Append operator OFF through privileged
   `app.set_pos_order_alerts(false, reason, operator_reference)` and verify the
   latest revision is OFF. This invalidates prior registration authority; preserve
   registrations/deliveries and every prior setting row. The owner switches HOME
   Inbox background alerts OFF (or notification Stop) and verifies actual silence;
   do not restart/Force Stop POS or change its printing/spool settings.
3. Disable Cron in the dedicated Vercel project's settings, then set
   `POS_ALERT_CRON_ENABLED=false` and deploy that reviewed OFF configuration.
   Remove the schedule through a later reviewed change. Changing a Vercel env
   value alone does not alter an existing deployment's env snapshot.
4. Inspect in-flight leases/queue and invocation status read-only. Retain all
   registrations, deliveries, audit events, orders and print evidence. Never
   delete queue rows, release leases manually or replay notifications to test
   shutdown. Rotate compromised credentials only through a separately approved
   coordinated procedure with both gates OFF.
5. Roll back source only to a reviewed no-schedule/OFF deployment. Vercel rollback
   can restore an older schedule/env snapshot, so recheck Cron and both flags;
   never treat rollback alone as a kill switch. Printing and order intake are
   independent and must not be changed during notification recovery.
