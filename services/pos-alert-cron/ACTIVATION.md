# Later installation / activation proposal — NOT EXECUTED

This is a review handoff, not an executable config or authorization. The deployed
`vercel.json` intentionally has no `crons` key. No project, schedule, credential
or hosted resource is created by this PR. Keep notification delivery OFF.

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

## Default-OFF installation acceptance

- Confirm exact reviewed source, dedicated project/root and production deployment
  identity/alias. No existing product project or custom-domain changes.
- Verify `vercel.json` has no schedule; hosted Cron list empty; both flags false.
- Missing/wrong inbound auth must not forward. With valid inbound auth and OFF,
  expect `503 disabled`; Preview must never forward even if accidentally enabled.
- Verify secret storage type/Production scope and no credentials in logs/bundles.
- Existing alert tables/queue metadata must show no scheduler claims or sends.
  Do not seed registrations, create orders or turn on FCM to verify OFF behavior.
- Preserve Maps Burger rollout 1265, printing BLOCKED revision 1264, all 625 holds,
  previous order/print evidence, official APKs and other devices.

## Separate reviewed activation change

Only a later owner-approved PR may add the following schedule to this project's
config, after the installation passes and Pro/Enterprise eligibility/costs are
approved:

```json
{
  "crons": [{ "path": "/api/dispatch", "schedule": "* * * * *" }]
}
```

This snippet is documentation only and must not be copied into current deployable
config. That later change must define a bounded HOME-only activation window and
its enforceable UTC cutoff/kill switch before enabling either flag. Preserve the
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
2. Disable Cron in the dedicated Vercel project's settings, then set
   `POS_ALERT_CRON_ENABLED=false` and deploy that reviewed OFF configuration.
   Remove the schedule through a later reviewed change. Changing a Vercel env
   value alone does not alter an existing deployment's env snapshot.
3. Inspect in-flight leases/queue and invocation status read-only. Retain all
   registrations, deliveries, audit events, orders and print evidence. Never
   delete queue rows, release leases manually or replay notifications to test
   shutdown. Rotate compromised credentials only through a separately approved
   coordinated procedure with both gates OFF.
4. Roll back source only to a reviewed no-schedule/OFF deployment. Vercel rollback
   can restore an older schedule/env snapshot, so recheck Cron and both flags;
   never treat rollback alone as a kill switch. Printing and order intake are
   independent and must not be changed during notification recovery.
