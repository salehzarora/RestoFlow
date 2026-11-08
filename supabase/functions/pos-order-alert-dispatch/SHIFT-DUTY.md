# Shift notification contract

A branch starts with no shift alert policy. An authenticated organization or restaurant
owner in that branch's scope, with AAL2, can set a policy revision and approve an absolute
alert end for an existing open shift. The approval is stored separately from financial
shift records. The original test contract used twelve hours from shift opening as a
fixture while the production cap awaited an owner decision.

The employee who opened the shift uses its paired POS while signed in. A foreground
preview reserves a fresh consent UUID on that installation. The employee sees the end
before confirming. Enrollment rechecks the matching employee, membership, device session,
shift, policy revision and end. The server fixes the cutoff at the earliest of the approved
end, shift opening plus the policy cap, and device session expiry. Each additional device
needs to qualify independently. Legacy registration continues to use its existing limit.

The duty permission permits alert status and transport maintenance. The cashier UI
still locks. A naturally elapsed PIN can leave the independent alert permission usable
until its cutoff. An explicitly ended PIN, a closed shift, a revoked membership or an
invalid scope denies that use. A later shift or policy revision needs fresh consent.
Status, token rotation, backgrounding and process recreation cannot issue a new grant.

The native status gateway has three duty routes. Each takes an installation UUID and
consent UUID. Status and token refresh require the status secret. Refresh also requires
the previous transport generation and a new FCM address. Revocation requires a distinct
revoke-only secret and echoes the targeted consent. The consent UUID is the stable
idempotency identity for that single revocation, independent of token rotations.
Unknown results cannot confirm an offline cancellation. Client OFF stops local effects
before network reconciliation. A recipient checks server eligibility and the local
monotonic cutoff. Network loss can delay observation of remote revocation.

A duty FCM hint uses version 2 and carries both consent and transport generation.
Pending and terminal hints trigger a fresh bounded status read. Only the current
response for that activation, local scope, transport generation and read order may
replace the pending set. V1 installations receive the original payload shape.

## Owner-approved initial rollout, 8 November 2026

The owner approved a limited official POS rollout to OPD2480 with a twelve-hour cap
from shift opening. The authorized owner must approve the alert end for the eligible
shift through AAL2. The employee must independently confirm consent for that device
and shift in the foreground. This approval covers OPD2480 only. Production rollout
and activation remain subject to verified release execution.

QA78 passed controlled background-process recreation with the package unstopped and
natural unplugged deep Doze. The owner heard each trial's alert while the screen was
locked, before opening QA. Independent client resolution cleared the alert in both
trials. The previous real long-idle trial crossed eight hours, two minutes and seventeen
seconds. Its human hearing result remains `NOT_VERIFIED`, accepted by the owner for
this rollout. The historical incident remains `UNKNOWN`.

The lab sender was invoked explicitly after each test request and resolution. The
existing automatic trigger's source contract was reviewed separately. Production
trigger operation requires verification during the authorized rollout.

The official Supabase application recorded migration version `20261108085442`.
The repository filename follows that recorded version. Its SQL bytes retain SHA-256
`7bd3b8946cde2979519a4e302c6c5ecef25399725234072df617359168b4a865`,
matching the reviewed source formerly named `20261106180840_bizbot_pos_long_shift_alerts_001.sql`.
Historical QA78 receipts keep their original tested filename and source identity.
