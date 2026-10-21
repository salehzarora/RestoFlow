# BIZBOT POS decision guard forwarding

Work ID: `BIZBOT-POS-DECISION-GUARD-FORWARD-001`.
Issue: #358, follow-up to #356 / PR #357.
Base: `d6bb31b1efee9c3fcb4f3293dd81ed761a553de0`.

## Reproduced failure and smallest correction

Both real POS boot paths wrap their transport in
`DeviceSessionGuardedTransport`. That wrapper previously omitted
`AuthenticatedWebOrderDecisionTransport`, so the provider-created
`RealOnlineOrderInboxRepository` refused both decisions locally with
`OnlineInboxException(unavailable)` before HTTP. The previous boot test fetched
the Inbox but never exercised a decision. New production-composition tests
reproduced both failures against the unchanged base before the fix.

The shared outer wrapper now exposes the existing capability. A blocked session
returns the existing transient `device_session_unverified` refusal; an unsupported
delegate fails closed. An allowed capable delegate receives the original body
exactly once, without awaiting between the guard check and handoff. The same
authenticated SDK client, Edge path, device proof, PIN, request and decision IDs
are retained. No legacy RPC fallback, automatic retry or new principal exists.
Ordinary RPC recovery allowlisting and guarded kitchen ACK code are unchanged.

Blocking while the repository awaits its device credential prevents the later
handoff. A request already delegated to the SDK can remain in flight: this fix
does not introduce the kitchen ACK boundary's late `isCurrent` callback into the
decision API or claim that blocking rolls back a committed decision. A timeout
remains uncertain and requires reconciliation with the original identity.

## Focused verification

The 19 new tests use actual `buildPosBootRoot` / `PosBootCoordinator` overrides,
the boot-created outer guard, provider repository and locked Supabase SDK.
Coverage includes both decisions, blocked and asynchronously blocked sessions,
normal recovery without replay, real degraded boot and permanent in-place
upgrade, missing inner capability, HTTP authorization/server errors and a late
response after timeout without another transmission.

Six scenarios also execute the real Edge handler through an offline Node adapter
and inspect its exact RPC handoff, public rejection reason, caller authorization,
device/PIN fields, authoritative denials and replay response. Only final HTTP/RPC
IO and credentials are synthetic. The adapter never opens a socket or calls
global fetch; it does not substitute for database JWT/tenant/RLS assertions.
Those remain covered by the existing isolated SQL/CI suites.

Existing auth identity, data remote, POS pairing/recovery/offline/controller and
real-SDK kitchen ACK suites are run unchanged. KDS/Kiosk regressions cover the
shared wrapper without authorizing a device update. Required CI also runs its
isolated migration/pgTAP/RLS suite. Local results and actual CI are recorded
separately in the PR; no production decision is used as a test.

## Release and physical acceptance

Use the next unused ledger reservation only after independent review and full
exact-source CI. The existing official runner builds the synchronized signed
pair from a clean audited source; POS keeps Firebase opt-in, KDS receives none.
Never overwrite or rebuild consumed v67. APK build authorization does not grant
PR merge or installation approval. No server deployment or migration is needed
for this client capability repair.

Keep existing ordering, notification/Cron settings, ordinary-print containment
and all protected historical holds unchanged. Do not reset data/pairing or retry
an uncertain decision. Owner acceptance remains pending: verify a legitimate
Accept and a separate Reject, public reason and keyboard behavior, plus the
two-device background cancellation test with no later order submission and
another pending request still covered. No historical print may be replayed.
