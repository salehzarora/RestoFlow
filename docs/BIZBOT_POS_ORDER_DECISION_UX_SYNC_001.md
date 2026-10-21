# Issue #356 — decision synchronization and rejection UX

Work ID: **BIZBOT-POS-ORDER-DECISION-UX-SYNC-001**. Base:
`8cb529f081cf92745ba81977dab97ab99348198d`. D-050 / API §4.54 record
the additive design. This is a platform-wide implementation, not a tenant patch.

## Findings and correction

The issue records terminal deliveries materializing minutes after decisions,
coincident with subsequent submission wakes. The existing SQL terminal scan
already discovers accepted, rejected and expired requests when the shared worker
runs. New `pos-web-order-decision` forwards the same real device JWT and personal
PIN/device proof to the existing atomic decision authority, then schedules a
bounded best-effort wake only for a validated new committed terminal result.
There is no new delivery queue or sender, synchronous FCM transaction, or worker
credential in POS. Replays and failures do not wake; failure to schedule/send does
not change a successful decision. The controller retains its original decision
identity for uncertain recovery, with no fallback decision RPC.
The existing authenticated web POS remains supported through exact product-origin
CORS (canonical and documented legacy host); native calls omit Origin. Preflight
never authorizes a decision, and all real POSTs retain JWT/PIN/device checks.

Android already had cancel-hint reconciliation and a 60-second audio tick. The
structural gap was a shared queued status read without an absolute completion
deadline; later hints could remain fenced behind it. Reconciliation now owns an
independent timer with the same 60-second cadence/5-second hint floor, a 20-second
queue/network/completion watchdog, HTTP cancellation, and lifecycle/binding
generation fencing. It always replaces the complete authorized pending set.
Neither an FCM cancel hint nor one resolved request suppresses another pending
request. This source defect is proven; the owner's exact native runtime failure
is not proven without device evidence.

Rejection uses a separate keyboard-aware route, with one inset owner, scrolling,
large-text/RTL support, draft retention across rotation, explicit public wording,
and current request/authorization validation at confirmation. Cancel/dismiss do
not decide. Trimmed Unicode reasons remain mandatory, at most 240 code points,
without ASCII controls.

Only the new explicit rejection RPC writes the private, forced-RLS, append-only
public-reason ledger atomically with the actual decision. Legacy reasons and
historical replays remain private. Capability-authenticated status optionally
projects `customer_rejection_reason` only when rejected. Storefront strictly
validates it and renders escaped, bidi-isolated plain text. No private-reason
fallback, backfill, contact logging or browser persistence is added.

## Separate live scheduled-execution evidence

Read-only Vercel CLI metadata during implementation found dedicated project
`prj_QVlsRLCT0IsnqHwhMoPzNq6D3Vos`, approved team
`team_yynO6ARGc6VsRrAB69hOTTZy`, with one `/api/dispatch` definition
(`* * * * *`) and **`enabled:false`**. Its definition host resolves through
read-only inspection to production READY `dpl_H4C7WR1CQ4Txkou3qJBF1iaDrk2d`.
No manual invocation was performed. The bounded runtime-log read supplied no
usable invocation records; it does not prove the absence of earlier executions.
READY/definition presence/instant-wake successes are not scheduled-execution proof.
This disabled platform switch is an independently established recovery gap;
it does not establish the sole cause of the owner's Android observation.

At `2026-10-20T21:28:33Z`, read-only database metadata showed 168 migrations,
operator enabled revision 6, two enabled registrations, 22 sent delivery rows,
625 historical holds, ordinary printing BLOCKED revision 1264 and existing
Maps Burger intake/target-print rollout revision 1279 enabled. Implementation
does not modify these production records or any operational gate.

## Reviewed rollout order and rollback

1. Obtain exact-head CI/security/RLS review and explicit owner merge approval.
   Keep live website ordering and notification authority ON throughout routine
   rollout; no registration, data, pairing, PIN or spool reset is a workaround.
   **Do not execute the merge, mark auto-merge, or deploy/promote the updated
   product web POS until steps 2–4 are deployed and independently verified.**
   Normal main Git automation can immediately rebuild `/pos`; its updated
   Accept/Reject transport requires the new decision endpoint. Product and
   Storefront deployments are not an ordered dependency chain. Stage steps 2–4
   from the exact owner-reviewed PR source in isolated checkouts, with source,
   target and deployment receipts, before allowing the main merge. If that
   predeployment path or a separately approved promotion interlock cannot be
   established, stop before merge; do not pause ordering or notifications.
2. Deploy the additive Storefront decoder/status UI first. Older already-open
   browser tabs have a strict decoder and may need a refresh before receiving a
   newly public reason. Older responses with the field omitted remain valid.
   Verify the actual `menu.bizbot.systems` deployment and source, not merely a
   Dashboard/Preview check or a successful product Git deployment.
3. Apply only `20261020212503_bizbot_pos_order_decision_ux_sync_001.sql`
   through the governed exact-version
   process. Independently verify schema, ACLs/RLS and migration history before any
   retry if the commit outcome is uncertain. No historical reason backfill.
4. Deploy the new decision Edge function and updated public response whitelist.
   Preserve existing submission, operator, sender and dispatcher settings. Verify
   authenticated denial and scoped behavior without creating production orders.
   Record successful schema/history, function identity/authentication and actual
   Storefront compatibility verification before the conditional main merge.
5. After that dependency gate passes, execute only the separately approved main
   merge and verify normal product Git deployment. Use the already verified
   official synchronized v67 artifacts from audited source
   `04445fdf019b4184ee0ce9fb9bbd8473b157db64`; code 67 is consumed and must not be
   rebuilt. v68 is a bookkeeping reservation, without build authorization. Preserve
   v66 artifacts and consumption receipt. KDS functionality and printing are
   unchanged; no KDS device update is required for this fix. Update eligible
   accepting POS in place during safe maintenance, retaining local state/settings.
   No automatic device action is part of source validation.
6. Separately restore the existing scheduled recovery path on the exact dedicated
   Vercel project after checking current continuous-mode authentication and
   notification controls. Do not rotate secrets or issue a manual Run as proof.
   Observe an actual platform-scheduled invocation with deployment/request/time
   metadata and the authenticated dispatcher result. The current disabled switch
   must be resolved before claiming reliable Cron recovery.
7. Perform the attended two-device acceptance below. Physical verification,
   Android policy/network limitations and operational readiness are separate
   from code/CI success.

Rollback: retain additive ledger data and historical privacy; redeploy the prior
decision client/route only after reconciling outstanding decision identities.
The old rejection RPC remains available and private. Never replay an order,
decision, print job or notification to prove rollback. Avoid a global OFF action
for routine rollout. An actual emergency uses the existing reviewed shutdown
runbook and preserves all evidence.

## Focused verification and physical acceptance

Offline verification covers SQL/RLS/tenant and capability isolation, legacy
privacy/no replay promotion, atomic rollback, authenticated Edge decision wakes,
replays/uncertainty/runtime absence/timeouts, mocked native timing/generations,
Flutter portrait/landscape/IME/large-text AR/HE/EN, and actual loopback Storefront
browser status rendering. No production order or real FCM delivery is generated.

For owner acceptance, use legitimate identified pending requests X and Y on two
eligible authenticated devices A and B. Keep B backgrounded/screen off, A active.
Accept X once; **do not submit another order afterward**. Verify B stops X while Y
continues alerting. Repeat with a separately authorized rejection: enter a clearly
customer-public reason, confirm once, observe the same cancellation/preservation
and the customer's capability-protected escaped reason. Also check keyboard and
rotation on the actual tablet. Record terminal commit, dispatch/FCM timestamps,
actual scheduled recovery metadata, native reconciliation/cancellation timing,
and owner observation separately. No print retry, test print or historic replay.

An unavailable network, expired PIN/registration, Android notification policy,
Force Stop or battery restriction is not a successful background delivery. No
physical cross-device success is claimed before the owner completes this check.
