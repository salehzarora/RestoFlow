# BIZBOT POS alert scheduler — default OFF

Work ID: BIZBOT-VERCEL-ALERT-CRON-001. This directory is a standalone Node 24
Vercel Functions project, with no dependencies, client bundle, database access,
Firebase credential, or deployment script. Existing application deployments and
the Supabase worker are unchanged. **No Cron schedule is registered.**

## Request boundary

`GET /api/dispatch` requires a constant-time authenticated inbound bearer, exact
explicit enablement, a Vercel production runtime, two different valid secrets,
the exact approved destination, and a valid, currently open UTC pilot window.
Each authorized invocation makes one HTTPS
POST with `{}` to the existing dispatcher. It forwards no incoming body, query,
Origin, or other header. Redirects and automatic retries are forbidden.

The overall upstream deadline is 115 seconds, including reading its response;
the Vercel function duration limit is 125 seconds. Successful HTTP status alone
is insufficient: the worker must return its existing bounded `{ok:true,sent,
deferred}` contract, with at most ten deliveries. Responses never include worker
content, credentials or exceptions. Application code emits no logs. Infrastructure
access logs must not capture Authorization headers or request/response bodies.

| Runtime variable | Required value / treatment |
| --- | --- |
| `CRON_SECRET` | Independent random 256-bit bearer, 64 lowercase hex; production-only Sensitive/Secret |
| `POS_ORDER_ALERT_WORKER_SECRET` | Different random 256-bit bearer matching Supabase Edge Secrets; production-only Sensitive/Secret |
| `POS_ALERT_CRON_ENABLED` | Defaults OFF when absent; only exact `true` enables |
| `POS_ALERT_DISPATCH_URL` | `https://oqmevrndtivqxgyvcmwy.supabase.co/functions/v1/pos-order-alert-dispatch` |
| `POS_ALERT_PILOT_START_UTC` | Required server-only Config, Production only; strict `YYYY-MM-DDTHH:mm:ssZ` or `YYYY-MM-DDTHH:mm:ss.sssZ` |
| `POS_ALERT_PILOT_END_UTC` | Same strict UTC format; later than start, at most 30 minutes after start |
| `VERCEL` / `VERCEL_ENV` | Platform-provided `1` / `production`; do not override |

The window is start-inclusive and end-exclusive. Missing, malformed, impossible
calendar dates, offsets, inactive windows and windows longer than 30 minutes fail
closed with `503 unavailable`, with no outbound request even when the enable flag
is true. Each invocation reads its configuration and server clock again. Its HTTP
deadline is the earlier of 115 seconds or the pilot cutoff. Aborting an in-flight
request cannot recall a worker/FCM send already underway. This guard does not
automatically turn off the Supabase flag, operator setting, Cron switch or native
Android delegation; the cutoff/shutdown procedure in [ACTIVATION.md](ACTIVATION.md)
is mandatory. Neither UTC variable has a default pilot value in source/config.

Both credentials are server-only, scoped solely to this future project's
Production environment. Do not share them with existing projects, Preview,
Development, custom environments, client-prefixed variables, or team-wide envs.
Use Vercel's write-only Secret type (legacy API `type: sensitive`,
`visibility: secret`, `target: [production]`). Source can enforce format and
separation; platform storage type/scope must be independently verified during
the separately approved installation.

Responses are `200 {ok:true}` on verified completion, `401` for bad inbound
authentication, `400` for query/body input, `405` for a non-GET method, `503` for
OFF or missing/invalid configuration, `502` for upstream failure, and `504` for
the deadline. All carry `Cache-Control: no-store`.

## Delivery semantics

Vercel Cron is best effort, not exactly once: runs can be missed, duplicated or
overlap, and failed invocations are not retried by Vercel. One POST per invocation
does not mean one global invocation. The existing Supabase row locks, unique
delivery identities, two-minute leases and bounded retry state are authoritative.
Do not add a process-local lock, alternate queue, order operation, or print action.

A timeout or connection error is an uncertain downstream outcome. Aborting this
HTTP caller does not prove the Edge worker stopped. Never immediately replay it
to force success; reconcile worker metadata and let its existing lease/queue
contract handle the next separately authorized scheduled tick. FCM messages are
untrusted notification hints, never order or printing authority.

## Local verification

From the repository root, with Node 24:

```sh
node --test services/pos-alert-cron/test/*.test.mjs
node --check services/pos-alert-cron/api/dispatch.mjs
node --check services/pos-alert-cron/lib/handler.mjs
git diff --check
bash tools/check_secrets.sh
```

Tests use public synthetic bearers and fake HTTPS only. They cover authentication,
configuration, preview/OFF, destination allowlisting, exact outbound isolation,
redirects, failures, body limits, deadlines, overlapping invocations and no logs.
They do not send a notification or establish deployed readiness.

## Installation and activation boundary

See [ACTIVATION.md](ACTIVATION.md) for the HOME-only pilot and shutdown runbook.
The dedicated OFF-only project is already installed; no credential rotation or
project creation is needed for this preparation. A new installation would create
a **separate** Vercel project with Root Directory `services/pos-alert-cron`, Node
24, framework Other, no application build/output overrides and no access to files
outside that root. Do not link/reconfigure Storefront, Dashboard, POS or KDS.
Deploy with `POS_ALERT_CRON_ENABLED=false` and no schedule first. Preserve
`POS_ORDER_ALERTS_ENABLED=false` in Supabase until separate activation approval.

Once-per-minute Cron requires a qualifying Pro/Enterprise plan. Verify plan,
cost approval, duration support and Cron access to the protected endpoint before
installation/activation; do not attach billing or weaken deployment protection
to work around an incompatibility.

References: [Node handlers](https://vercel.com/docs/functions/runtimes/node-js),
[Cron authentication and delivery](https://vercel.com/docs/cron-jobs/manage-cron-jobs),
[Cron plan limits](https://vercel.com/docs/cron-jobs/usage-and-pricing),
[Secret environment variables](https://vercel.com/docs/environment-variables/sensitive-environment-variables).
