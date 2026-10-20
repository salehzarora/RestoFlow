# Platform online-order acceptance fixture (#353)

`local-acceptance.mjs` exercises the production submission, notification
dispatcher and native-status handlers against a disposable PostgreSQL database
through actual local PostgREST HTTP calls. It uses the already isolated
`bizbot_platform353_pg_20261020` fixture, clones its migrated database into a
**new** single-use database and starts its own PostgREST container on loopback.
The cached Node test container and PostgREST share the fixture's network
namespace: HTTP binds only `127.0.0.1:3000`, on an internal Docker network with
no external gateway. This avoids Windows Docker port-forwarding assumptions.
It never connects to Supabase, Google, a POS device or a printer.

The FCM OAuth provider and physical FCM transport are synthetic capture
adapters; the production message constructor and database delivery/lease code
are real. A single kitchen transport capture is counted only after the real
irreversible begin RPC returns `send_authorized=true`. This establishes local
protocol integration, not Android delivery, audible notification or paper.

Prerequisites: the task-owned PostgreSQL fixture must already have all migrations
applied; Docker must have the pinned PostgreSQL and PostgREST images cached.
The runner rejects another fixture identity, non-loopback requested port binding, an
external Docker network, an existing execution database or PostgREST container,
and any HTTP URL except its own loopback API and intercepted FCM endpoint.
The PostgreSQL clone preserves managed object ownership/ACLs; the task-owned
local cluster administrator restores it without changing the source database.
All fixture identities and credentials are explicitly synthetic.

Run from the repository root with the existing Node 24 runtime:

```powershell
$env:BIZBOT_PLATFORM353_LOCAL_ACCEPTANCE = 'LOCAL_SYNTHETIC_ONLY'
node tools/platform_online_orders_353/local-acceptance.mjs --run
```

The runner prints one sanitized JSON report. It preserves its new database for
review and removes only its own PostgREST container in `finally`. Existing
containers/databases, production, official Android artifacts and other
worktrees are untouched. Repeating it creates a fresh database; it never resets
or reuses a previous execution database. Retry and expiry cases advance only
synthetic fixture facts. Expiry uses a transaction-local trigger bypass solely
inside the guarded local fixture database; production receipt immutability and
the real expiry/reconciliation code are unchanged.

The integration assertions cover new tenant publication, paired-device
registration, authoritative menu availability, submission/replay, multi-device
Inbox and FCM fanout, cross-tenant denial, concurrent Accept with independent
decision identities, one canonical order/dispatch and irreversible send,
terminal cancellation, fresh-device onboarding, pairing revocation, Cron retry,
offline-printer retention, expiry, token-refresh generation compare-and-swap,
and emergency OFF without queue mutation. The dispatcher returns `503` when
OFF; Cron preserves its existing `502` upstream-failure contract in that case.
