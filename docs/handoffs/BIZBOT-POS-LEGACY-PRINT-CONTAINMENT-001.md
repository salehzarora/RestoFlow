# BIZBOT-POS-LEGACY-PRINT-CONTAINMENT-001

Source-only correction. Controlled physical acceptance remains ON HOLD.
The previous HOSTED-INSTALL PASS establishes installation, not safe physical
acceptance or protection of other printer-capable devices.

## Isolation and contract

Baseline `faafd614b2aaabfed3bd0f5c1f9ed419e6edd74e`; isolated branch
`fix/BIZBOT-POS-LEGACY-PRINT-CONTAINMENT-001`. Primary checkout remains on
`556136f1c3c2b3a59c300058a7fe1a82db444fc7`, with its existing 96 untracked
entries preserved. Open PRs #314 and #315 have no path overlap. Other tracked
dirty files observed at preflight belong to dashboard cards/shell, Android
Gradle/manifest experiments, and the modifier-selection sheet/test; none are
inputs to this change. No other worktree changes are absorbed.

New additive migration `20261015013558_bizbot_pos_legacy_print_containment_001`
does not modify or reapply migration `20261014184409`. Installation alone
creates no hold, policy, attempt, order or dispatch.

`kitchen_print_dispatch_holds` is an immutable, forced-RLS private audit table.
A row means **automatic retransmission prohibited pending review**. It does
not assert printing, transport acceptance, completion, ACK or supersession.
Application roles, including service_role, have no direct table privileges and
no mutation RPC. A separately authorized privileged operator must submit exact
dispatch, organization/restaurant/branch, snapshot time, full-row MD5 fingerprint,
manifest SHA-256, reason and operator reference. The insert trigger validates
the locked dispatch against the fingerprint and scope, and refuses target
enrollment. There is no release/expiry/backfill or synthetic attempt contract.

Branch policy is separate append-only audit history: ordinary, blocked, or
target_only with one request UUID and a short expiry (at most one hour).
Expired target_only evaluates to blocked. A newer explicit operator policy is
required to resume ordinary work; it cannot remove dispatch holds.

`pos_kitchen_print_containment(p_device_id uuid,p_session_token text)` requires
an authenticated real paired POS session and derives scope server-side. It
returns safe scope IDs, revision, mode, target request/expiry and held dispatch
IDs. It does not grant printing or return customer data. Existing session
renewal remains the authentication authority. Target begin/claim and broad
pull consult the same policy; status/finish reconciliation remains available.

## Concurrency and local evidence

Hold/policy insertion takes an exclusive branch advisory transaction lock.
Broad pull, targeted operations and policy reads take its shared counterpart
before hierarchy and dispatch locks. READ COMMITTED is required; a stale
repeatable-read snapshot cannot authorize work. After lock waits, the writer
rechecks exact dispatch scope/fingerprint; the pull rechecks holds and policy
after dispatch locking as well as in candidates, returned page and has_more.
A pull that wins before a hold can already have returned a row; the POS guard
is essential for that case. A hold that wins first prevents the waiting pull
from claiming or returning it. This is not a remote byte-revocation protocol.
An online policy RPC releases its server lock when it returns; it does not hold
a distributed lock over Bluetooth/TCP. Therefore policy/hold activation requires
all senders quiescent, including online senders already inside the destination
gate. The guard covers activation while a job is waiting on that gate, not
revocation after a transport has begun.

Production native composition installs the containment guard before exposing
the runtime to lifecycle callbacks. Unknown policy blocks ordinary work.
Target-only mode blocks ordinary drain/import/send on startup, resume and
delayed callbacks. A stale pulled page is checked again before row import and
ACK. Worker selection skips held jobs without exhausting its FIFO window.
The guard is re-read inside the shared destination gate before markPrinting,
begin or either network/Bluetooth send. Policy denial writes no result or ACK.
Existing pending ACKs for held dispatches are retained without automatically
flushing them. Genuine crash/transport evidence remains evidence; a policy hold
is never used as its substitute.

Import and ACK authorization now evaluates the operation, current scoped policy,
exact holds and (for a target) the validated server claim tuple together. A
permit is tied to that policy observation, controller/session generation and
target lifetime; later observations, failures or scope changes invalidate it.
Import checks it immediately before invoking the durable insert. A restriction
learned while that asynchronous insert completes leaves durable, unACKed and
nonrunnable evidence for reconciliation, not a fabricated completion.

Every native spool ACK path, including mirrors, worker outcomes and pending
retries, requires the guarded transport capability after credential loading.
The POS bootstrap constructs the SDK client and its injected HTTP boundary as
one binding. SDK body preparation and token refresh complete before the boundary
checks the exact endpoint, operation, immutable payload and current permit,
then synchronously hands off to the effective HTTP client's send. Private
per-invocation Zone context never enters headers, URLs or logs. Missing/stale
context or unsupported composition defers locally; auth and policy reads remain
independent. Direct/local ACKs retain their separate exact invocation context
and normal SDK authentication. Local denial retains pending markers and retry
metadata. Protected redirects are disabled; the locked SDK does not retry POST.
Contexts expire when the invocation ends, including a timeout before handoff.
A late SDK continuation cannot revive one. Socket work after HTTP handoff is
not retractable, and an already-delegated outcome/uncertainty remains evidence. A
restriction after genuine transport evidence was recorded defers its ACK without
erasing that event; valid permission can later reconcile the same evidence
idempotently without another send. An ACK already handed to HTTP cannot be retracted;
its real response is honored. Exact-target finish/status recovery stays on its
separate reserved-attempt contract, and ordinary pending flush does not send
target outcome ACKs. Direct/offline printing outside the spool is unchanged.

Destination ownership distinguishes positively permitted work, an exact
immutable dispatch hold, a branch/target block, and unknown/transient policy
failure. Only the exact immutable hold permits excluding a same-scope QUEUED
owner without altering its row. Branch/target blocks and unknown/transient
failures preserve that owner and defer its destination; they cannot justify a
second queued owner. Deferred siblings are skipped before the bounded worker
window so independently safe destinations may progress even behind a long
same-printer backlog. PRINTING rows never qualify for exclusion. The store
rechecks status and full scope transactionally; the shared destination gate
still serializes physical sends and rechecks permission before markPrinting.
Once healthy reads return, the existing owner and subsequent eligible jobs can
progress without competing owners or invented outcomes. Genuine prior printing
and transport evidence are retained. No backlog claim-and-ACK reconciliation is
introduced.

Native secure storage retains scope/session-bound policy and monotonic held
IDs as restriction evidence. A cached ordinary record is never a durable
positive grant for server-imported spool work after a new controller/process
starts. This is necessary because a disk record can remain ordinary when a
later restrictive write fails or the process dies. The new controller must
obtain a fresh correctly scoped paired-session response and successfully
persist it before acquiring process-bound ordinary authority. With that
authority, the same live controller can process unheld server-imported work
offline; it does not obtain positive authority merely by rereading disk. The
direct genuine ordinary/offline POS printing path retains its existing valid
authorization, outbox and mirror rules without an unconditional new RPC.

A valid scoped blocked, target-only or newly held response becomes restrictive
in memory before any cache write is awaited. Restrictive write failure retains
the learned mode/holds and revokes ordinary authority. Network/cache failure
cannot roll back a learned restriction. Different session/scope, target-only
expiry and unknown cache never release backlog. Same-cache-key writes are
serialized with controller generations; a superseded controller's delayed
response/write cannot install authority in the new controller. Restrictive
cache recovery may preserve more denial; it is never proof of permission.

## Cache crash and failure boundaries

The positive authority described above exists only in the current controller,
not in the secure-cache bytes. The stale-disk failure is therefore closed by an
authorization-validity rule, not by assuming that deletion or another write to
the same failing store will succeed. Preserve existing rows and keys throughout.

| Boundary | Required result for affected server-imported work |
|---|---|
| Process dies before receiving a new restriction | The process loses its authority; a fresh controller blocks until a fresh scoped response is successfully persisted. A fully offline client cannot learn a server change, so all senders must already be quiescent before activation. |
| Restriction decoded; cache write pending | Its mode and held IDs already deny affected work in memory. No worker may fall back to the former ordinary policy while waiting. |
| Restrictive write fails | Learned restrictions remain; ordinary authority is revoked. No best-effort invalidation is treated as proof that old disk bytes are safe. |
| Process dies during/after the failed write | Old, partial, unreadable or recovered cache bytes cannot grant ordinary authority to the fresh controller. Held identities missing from old disk cannot make their work eligible. |
| Ordinary response received but write has not succeeded | No new offline authority is created. Crash, write error or supersession cannot turn this unfinished read into a durable grant. |
| Fresh ordinary response successfully persisted | Only the current correctly scoped controller acquires authority; learned exact holds remain enforced. Restart still requires a fresh read/write before ordinary server-imported work. |
| Scope/session changes or old response completes late | The new controller starts without authority. Per-key serialization and generation checks prevent obsolete completion from restoring authority or replacing a newer restriction. Any leftover disk record remains nonauthorizing on startup. |
| Cache cannot be read or storage/key is unavailable | Fail closed for affected server-imported work; preserve storage, queued evidence and keys for diagnosis. Do not wipe, reprovision a populated spool or fabricate an outcome. |

This rule deliberately does not promise unattended offline restart of imported
printing work. That work waits for fresh paired-session policy verification.
It does not add that requirement to a genuine direct/offline POS order's
existing authorization/provenance path. A successful RPC is not a distributed
transport lock, and these crash rules cannot retract bytes already entering
Bluetooth/TCP; activation still requires quiescence.

**Offline/older-client boundary:** an offline client cannot discover a newly
activated server hold. Older APKs have no local guard at all. Neither server
holds nor readiness can revoke bytes already transmitted or queued on those
clients. Every printer-capable device must be inventoried and quiesced before
hold activation, then corrected clients must hydrate the approved policy while
online before being allowed to operate offline. Do not claim fleet-wide
containment while an unguarded or unreconciled printer-capable client can run.

## Target-only initialization

The bounded path inspects file presence (absent/present/unknown), opens only the
dedicated spool, counts TOTAL rows and evaluates the existing key flow before
targeted claim. Missing key is provisionable only at proven total rows zero.
Zero unresolved jobs is not that proof. Unknown presence/count, corrupt or
unavailable storage/key, and missing-key-with-rows return typed BLOCKED
diagnostics without wiping data or replacing a key. Genuine initialization is
followed by the existing read-only readiness probe/report; no readiness override
is introduced. Ordinary work is still policy-blocked even if readiness qualifies.
Any pre-initialization in-flight heartbeat is awaited, followed by one fresh
sample. This bounded second sample prevents joining old absent/keyless evidence.

Exact request/order/decision/dispatch/attempt/printer checks and the irreversible
begin fence remain intact. Only the original successful begin authorizes one
send. Unknown/lost begin, crash, duplicates or post-begin failure require
reconciliation, never another order/dispatch/attempt or automatic resend.
Lost finish may be reconciled idempotently. Transport acceptance is not paper.

## Unapplied candidate manifest

Local evidence outside Git:
`C:/Users/saleh/Desktop/ClaudeAi/RestoFlow/evidence/BIZBOT-POS-LEGACY-PRINT-CONTAINMENT-001/candidate-legacy-holds.json`
and `candidate-legacy-holds.sha256`.

Snapshot: `2026-10-15T01:40:26.407427+00:00` (04:40:26 Asia/Jerusalem).
Project `oqmevrndtivqxgyvcmwy`, organization
`20605c2b-3145-4803-a990-bbec3d9c1096`, restaurant
`de3bbc64-edad-4ff4-bccd-c2ef217c1d56`, branch
`2847c0be-3e31-45a5-957c-508729f1971e`.
617 exact candidates: initial_order 469, service_round 69, void 78, order_edit 1.
This count is a snapshot, not authorization for a future unbounded operation.
SHA-256 of the exact JSON bytes:
`01ea461c707e582750237bebe5d8eb1a6c4a9cb842c3aa99b0d81ccb313fd062`.

Owner-observed dispatches `abddb659-0342-41fd-9138-d273f2e3fe3c` and
`012ea5d9-5495-44d8-bb1c-747902a1aabb` are included. Owner paper testimony is
explicitly distinct from database transport/ACK evidence. The manifest exposes
no customer payload, private credentials or printer endpoints. Each fingerprint
is `md5(to_jsonb(dispatch_row)::text)` computed by PostgreSQL at the snapshot.
If any row changes before eventual application, stop and reconcile; do not
substitute a newly computed fingerprint under the old approval.

## Separately gated rollout — NOT authorized by this work item

1. Review/approve source and exact manifest independently of this local report.
   Keep all admission OFF, permit absent and channels disabled. No physical test.
2. Inventory all paired printer-capable devices. Owner quiesces them before any
   readiness, restart or installation can drain old queues. Record existing
   pairing, settings, outbox and local queue evidence; do not wipe or claim/ACK.
3. Under separate hosted authorization, apply only the new additive migration
   and install a reviewed BLOCKED policy plus the exact manifest in one bounded
   operator transaction. Take the common exclusive branch lock first; verify
   manifest file hash, every exact scope/ID/fingerprint and target exclusion;
   insert only those IDs, verify exact cardinality and unchanged original rows.
   No INSERT SELECT against an unbounded live eligibility predicate. Any changed
   fingerprint or unavailable evidence stops the transaction for reconciliation.
4. Use the next official Android release process (v61 is reserved), with separate
   preparation/build/record/update authorizations. Do not rebuild, relabel or
   overwrite v60. Install corrected POS in place while all other capable clients
   remain quiescent. Before any lifecycle worker can run, the guard must already
   be compiled and the server policy BLOCKED. Unknown/missing RPC fails closed.
5. While online, verify exact policy/holds on every corrected capable client,
   preserved keys/queues/settings, typed readiness and no unrelated sends. Any
   older capable client stays stopped; merely applying server holds is inadequate.
6. Separately approve one target UUID/short-lived target_only policy and the
   controlled admission permit. Bootstrap genuine readiness without ordinary
   drain; execute one specifically approved request/acceptance. Owner must verify
   physical paper separately. No broad-pull/reprint workaround.
7. Switch admission OFF immediately; remove the permit and disable channels.
   Record a BLOCKED policy after the test; expiry alone remains blocked. Resume
   ordinary operation only under a further explicit operator policy after fleet
   verification; immutable legacy holds remain effective. Preserve order/audit
   evidence and investigate uncertainty rather than deleting or fabricating it.

## Abort and rollback at every rollout boundary — HANDOFF ONLY

Do not execute this section during source correction or review. Each later
boundary requires its own explicit owner authorization. At every abort, close
general and controlled admission, remove the test permit and disable channel
submission flags through the separately authorized operator procedure. Confirm
their actual state; a failed switch-off is an incident requiring immediate
owner escalation, not permission to continue the test.

**Admission OFF does not stop an existing printing backlog and cannot revoke
bytes already entering transport.** Keep every printer-capable device quiescent
until its guarded lifecycle and exact policy/holds are verified. Include older
and offline clients; stopping one owner tablet is not a fleet inventory.

| Rollout boundary / failure | Safe stop and recovery |
|---|---|
| Source or manifest review not approved; identity/hash/scope drifts | Stop before installation or hold application. Keep admission closed and devices quiescent. Preserve the reviewed bytes and snapshot. Reconcile changed identities under a new explicit decision; do not refresh fingerprints or expand the 617-ID authorization silently. |
| Device inventory, quiescence or local evidence is incomplete | Do not activate readiness, restart POS, install or start any worker. Locate every capable device and preserve pairing, queues, keys and settings. An unavailable/offline older client remains stopped; no server-only claim of protection is valid. |
| Additive migration fails | Preserve the actual migration result. Do not reset/repair history or improvise rollback SQL. Keep devices stopped and admission closed; obtain a reviewed repair plan before retrying the failed step. |
| BLOCKED policy/exact-hold transaction fails or its outcome is uncertain | Do not start clients. Reconcile whether the transaction committed using read-only exact ledger/hash/scope evidence. Preserve any successful policy/holds. Do not bulk-ACK, manufacture completed/printed states, remove containment schema or rerun an uncertain operation blindly. |
| Corrected APK preparation/build/verification/update fails | Keep all printer-capable clients quiescent and admission closed. Preserve existing v60 artifacts and installed data. Do not resume v60 or another unguarded older APK as a rollback; do not uninstall, clear queues/storage or reset pairing. Use a separately approved corrected release/update plan. |
| Guarded startup/hydration, cache write, scope or readiness check fails | The client remains blocked. Preserve cached restrictions, DB rows, spool/key material and diagnostics. Do not force readiness, replace a missing key with rows, invoke broad pulls or use Test Print/reprint as a workaround. Verify no older client resumed before continuing. |
| Test permit/target-only policy is expired, wrong-scope or uncertain | Close admission/remove permit/disable channels and keep devices quiescent. Expiry/unknown policy remains blocked; it never releases the ordinary backlog. Reconcile the exact request and policy before any separately authorized retry. Do not substitute a second target request. |
| Submission/acceptance response is lost or uncertain | Close intake and preserve the request, decision, canonical mapping and audit trail. Use the existing read-only/status and authorized decision-recovery contract; do not create a replacement request/order or click Accept repeatedly to force output. |
| Target begin, transport or finish outcome is uncertain; app crashes | Preserve the irreversible reservation, attempt identity, local queued/printing evidence and audit rows. Reconcile the exact original attempt; never issue another automatic send, replacement dispatch/attempt/order or fabricated transport completion/ACK. Owner inspection is required for paper; a database record is insufficient. |
| Post-test switch-off or final fleet/policy verification fails | Treat the test as stopped, not successful release. Keep devices quiescent and escalate any gate that cannot be confirmed closed. Preserve the BLOCKED/target policy, immutable holds and reservations. Ordinary operation resumes only after separate explicit policy authorization and verified corrected fleet state. |

Rollback here means closing new intake and retaining containment while a
reviewed forward repair is prepared. It does not mean dropping the hold ledger,
reverting the guard migration, automatically expiring/releasing holds, removing
target reservations, draining/wiping queues, deleting audit rows, or fabricating
completion/ACK cleanup. Immutable legacy holds remain effective after a target
test or ordinary-policy decision. Existing authentic transport/crash evidence
must remain intact even when inconvenient.

If output is uncertain, preserve and reconcile it with the owner instead of
automatically resending. Do not infer paper from transport acceptance, database
dispatch state, a successful migration or a printer's connected indicator.
Physical acceptance stays ON HOLD until a later explicit authorization.

No push, PR, merge, hosted mutation, deployment, APK build/install, device action,
order, claim/begin/accept call or physical printing is performed by this task.
