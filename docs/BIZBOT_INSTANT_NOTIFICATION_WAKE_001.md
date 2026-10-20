# BIZBOT-INSTANT-NOTIFICATION-WAKE-001

Local implementation only, based on main
`3ade91f6df2668e57827229e16428d98134d9dbe`. No push, PR, deployment,
configuration, SQL, notification, order or device operation is authorized.

## Contract

After the normal live submission RPC returns a validated successful NEW Maps
Burger pending result (`replayed=false`), the Edge handler constructs its unchanged
checkout response and hands one promise to `EdgeRuntime.waitUntil`. This is a
best-effort batch wake, not guaranteed instant delivery or a new queue. The RPC's
receipt/live enrollment remains the durable source of notification work. Status
reads, controlled test/pilot routes, replays, non-pending responses, business
failures and uncertain outcomes never schedule a wake.

`POS_ORDER_ALERT_INSTANT_WAKE_ENABLED` is a new server-only opt-in, OFF unless
exactly `true`. It neither enables checkout nor grants notification authority.
The wake also requires the existing Edge master flag, valid Edge pilot window,
exact approved Supabase URL and existing independent worker bearer. It sends one
POST `{}` to the fixed dispatcher URL, without redirects or retries. No customer
fields, request IDs, capabilities, service key or incoming browser headers are
included. Nothing about scheduling is added to the public response.

Missing runtime, synchronous scheduling failure, asynchronous rejection, network
failure, invalid configuration and response timeout cannot change checkout. The
wake budget is at most five seconds, capped by remaining pilot time; it covers
headers, body reading and cleanup. Response bodies exceeding 4096 bytes are
abandoned; bytes are discarded. Cancellation is never awaited indefinitely.
There are no sensitive logs, and no response body is forwarded or retained.

The worker still leases up to ten oldest eligible deliveries. This wake need not
send the just-created request first and may process other authorized pending,
retry or terminal hints. There is no per-request claim filter. Registration,
scope, operator authorization, uniqueness, lease identities, attempt limit,
invalid-token handling and Firebase message construction remain unchanged.
Concurrent wake/Cron invocations use database leases, never process-local locks.
Unknown FCM outcomes can duplicate hints; hints confer no order/print authority.

## Mandatory Edge pilot authority

Every dispatcher caller, including Vercel Cron, now requires these server-only
Edge settings, with no defaults:

- Existing `POS_ORDER_ALERTS_ENABLED=true` and correct worker authentication.
- `POS_ALERT_PILOT_START_UTC` and `POS_ALERT_PILOT_END_UTC` strictly formatted as
  `YYYY-MM-DDTHH:mm:ssZ` or `YYYY-MM-DDTHH:mm:ss.sssZ`, with real calendar dates.
- Start before end, duration at most 30 minutes, and `start <= server UTC < end`.

Missing, offset/local-time, normalized invalid dates, whitespace, nonfinite clocks,
expired, future or overlong windows deny dispatch before OAuth or queue claims.
The handler rechecks the original window and master flag after OAuth, before
claiming and before each send. Changing/extending a window does not renew an
in-flight invocation. A send already issued before cutoff can finish afterward;
its existing finish RPC still records the outcome. Unsent leased rows remain
intact for later authorized recovery; no artificial send result is fabricated.

Vercel retains its independent authentication, flag and UTC checks. Future
operators must install the **same exact approved window** in both platforms. If
snapshots differ, each caller must satisfy the Edge window and Cron must also
satisfy Vercel's window; the stricter intersection applies to Cron. The direct
wake does not depend on Vercel's feature flag or platform Cron switch. Turning
only Cron OFF is therefore not a complete notification shutdown.

## Cron and timeout limitations

Cron remains necessary for the commit-to-wake crash gap, unavailable runtime,
unknown RPC response, lost wake, oldest-first batches, deferred retries (at least
one minute), lease recovery, accepted/rejected cancellation and logical expiry.
Terminal hints are produced only for requests already recorded by the notification
ledger. Neither expiry nor a decision triggers an additional submission wake.

Aborting the wake's HTTP request cannot recall dispatcher work or FCM already in
flight. The existing worker's individual HTTP timeout currently bounds response
headers; its body reads are byte-bounded but do not have a complete deadline.
This change bounds the new wake end to end, **not the whole downstream worker**.
Do not infer exactly-once FCM or a strict worker-completion deadline from the
two-minute lease. No sender/lease/schema redesign is included here. SQL and
Android/device behavior were not revalidated by mock-only tests.

## Later activation gates - not authorized by this preparation

1. Obtain review and separate push/PR/merge authorization. Obtain separate
   deployment authorization; do not assume Git publication applies Edge source.
2. Keep Edge notifications/operator/instant-wake OFF, Vercel forwarding OFF and
   platform Cron disabled while deploying the reviewed submission and dispatcher
   functions. Keep both platforms' pilot timestamps unset until approved. Current
   project settings alone do not prove a deployment's effective environment.
3. Independently verify exact deployed source and effective OFF state using a
   separately reviewed safe method. Do not retrieve secret values or invoke the
   worker as part of this local preparation.
4. Complete the pending HOME identity migration through its **separate** approved
   application workstream while notifications are OFF. This change does not edit
   that migration or arm/run its owner application runner. Retargeting alone
   neither registers HOME nor authorizes printing.
5. Obtain a fresh attended HOME pilot approval: one explicit UTC interval of at
   most 30 minutes, matching snapshots on both platforms, available shutdown
   operator, existing authenticated HOME registration and exact device scope.
   Do not enable any gate, create orders or send a test notification now.
6. During a later authorized pilot, observe notification latency and ordinary
   resolution separately from physical device evidence. A successful worker
   response is not proof of device display/audio or printing.

Emergency shutdown under its own authorization: set Edge
`POS_ORDER_ALERTS_ENABLED=false` first, instant-wake OFF, operator alerts OFF,
Vercel forwarding OFF and platform Cron disabled. Verify effective states and
owner-observed cessation. Cutoff stops new dispatch work, not existing native
authority or in-flight hints; preserve every order, registration, lease and print
record. No reset, replay, ACK, reprint or destructive rollback is a shutdown step.

Preserve Maps Burger rollout 1265, printing BLOCKED 1264 and all 625 immutable
holds. This change does not grant printing authority or modify POS/KDS/APKs.

## Offline verification scope

Existing CI globs include all new `.test.mjs` files without workflow changes.
Tests inject synthetic env, fake HTTP and clocks only. Submission and dispatcher
tests cover suppression, response equivalence, runtime failures, stalled bodies,
pilot validation, authentication and cutoff during awaits. The real Cron,
submission, dispatcher and FCM payload code also run against a shared in-memory
lease oracle for concurrent wakes, missed wakes, retries, uncertain finish and
terminal/expiry recovery. That simulation verifies integration wiring; it is not
PostgreSQL concurrency, hosted acceptance or physical Android coverage. No SQL
suite, actual order, FCM send, production connection or printer is used.

Runtime reference: [Supabase background tasks](https://supabase.com/docs/guides/functions/background-tasks).
`waitUntil` work remains subject to Edge worker limits and is not a durable queue.

## Local changed-file inventory

Production Edge source (five files):

- `supabase/functions/_shared/pos-order-alert-pilot.mjs` (new): strict Edge pilot checks.
- `supabase/functions/web-order-submit/instant-wake.mjs` (new): isolated bounded wake.
- `supabase/functions/web-order-submit/handler.mjs`: new-live-only post-commit hook.
- `supabase/functions/web-order-submit/index.ts`: runtime `waitUntil` adapter.
- `supabase/functions/pos-order-alert-dispatch/handler.mjs`: mandatory pilot checks.

Offline tests (four files):

- `supabase/functions/web-order-submit/test/instant-wake.test.mjs` (new).
- `supabase/functions/pos-order-alert-dispatch/test/pilot.test.mjs` (new).
- `supabase/functions/pos-order-alert-dispatch/test/wake-cron.test.mjs` (new).
- `supabase/functions/pos-order-alert-dispatch/test/alerts.test.mjs`: valid synthetic pilot configuration.

Documentation (two files): this document and
`supabase/functions/pos-order-alert-dispatch/CONTRACT.md` (Edge gate/wake contract
and correction of the unsupported whole-worker deadline claim).

Independent security/race and test-coverage reviewers both returned **APPROVE**
with no open blocking findings. Their review was read-only, with no SQL or hosted
access. The security review's minor response-byte wording correction was applied.

## Local verification result

Windows, existing Node v24.19.0, one combined final run:

```text
node --test supabase/functions/web-order-submit/test/*.test.mjs supabase/functions/pos-order-alert-dispatch/test/*.test.mjs services/pos-alert-cron/test/*.test.mjs tools/vercel/ignore-build.test.mjs
```

**475 tests: 473 PASS, 0 FAIL, 2 SKIP.** Skips are the unchanged deployment-filter
cases requiring POSIX newline/tab filenames and raw invalid-UTF-8 filenames.
The full filter suite passed, including Supabase-only changes ignoring all three
existing application deployments. This is Windows evidence, not a new Linux CI
or actual EdgeRuntime execution result. Existing CI globs already include the new
tests; no workflow was rerun and the uncommitted candidate has not been pushed.

Syntax checks passed for all nine changed/new `.mjs`/`.ts` source and test files.
There is no repository-wide JavaScript lint/formatter target for these modules;
syntax, scoped whitespace/endline checks and `git diff --check` passed. The
existing secret guard passed across tracked and nonignored files, using the
unchanged script with line endings normalized in memory for Git Bash. No tracked
guard file was edited. No Flutter/APK, SQL, database or live FCM test was run.

The HOME retarget migration's Git blob still hashes to
`913b15ca3b58c4181d3c77d18f5b9e39658ac1df00098137d003ee9b8643fdb6`.
The fresh Windows checkout has only Git's CRLF conversion; it was not rewritten
or used for application. The existing unarmed owner runner still hashes to
`10f9bb9b88f42696de392a833371ce8aa7e82622f01486bd5217f193df6a19f0`.
Neither the migration workstream nor any other worktree was modified.
