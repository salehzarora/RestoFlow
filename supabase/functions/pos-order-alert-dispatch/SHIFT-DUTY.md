# Shift notification contract

A branch starts with no shift alert policy. An authenticated organization or restaurant
owner in that branch's scope, with AAL2, can set a policy revision and approve an absolute
alert end for an existing open shift. The approval is stored separately from financial
shift records. The production cap and the operational process for recording that end
require an owner decision. Twelve hours from shift opening is a test fixture.

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
