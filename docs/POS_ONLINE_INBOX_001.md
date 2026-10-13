# POS-ONLINE-INBOX-001 — authenticated pending pickup inbox

Owner authorized implementation only on 2026-10-14. Baseline is merged
WEB-ORDERS-001 at `7db7076047fe636d88b9cc0ce1c14d2278e30029`. This packet records
scope, security and acceptance criteria before implementation (proposed D-046).
No hosted migration, deployment, live ordering or delivery activation is included.

## Authority and scope

Three new authenticated public INVOKER RPCs delegate to private app DEFINER bodies
with an empty search path. Every call requires the real device ID, raw device
session token and PIN session ID. The existing anonymous GoTrue POS bootstrap is
an authenticated transport envelope, not a human staff identity. `auth.uid()` must
exist, but it is never treated as the employee or compared to staff membership.
Staff identity and full organization/restaurant/branch scope derive only from the
token-proven paired POS device, its matching live PIN, employee and membership.
Revoked, expired, tombstoned, wrong-class and out-of-scope authority fails closed.
Allowed operational roles match canonical creation: cashier, manager,
restaurant_owner and org_owner. Acceptance derives and locks the existing real open
shift for the exact device/scope; it accepts no client shift or money authority.

Existing web-order tables keep their direct-access denial and immutable quote.
A new private append-only `web_order_decisions` ledger records real staff/device/
PIN attribution, a stable decision identity and the terminal mapping. Its policies
are four explicit per-command denials, never FOR ALL. No customer capability,
token, contact or free-text reason is stored in that ledger. Rejection reason is
kept in the existing private request. Existing canonical order audit stays intact.

## RPC contract

All three return JSONB and require `p_pin_session_id uuid`, `p_device_id uuid`,
`p_device_session_token text`:

- `pos_web_order_inbox`: optional `p_request_id uuid`, cursor
  `p_before_created_at timestamptz` + `p_before_id uuid`, and `p_limit integer`
  (default/max 50). Normal reads return unexpired pending requests in deterministic
  creation-time/ID order. A targeted lookup also resolves terminal/effective-expired
  state for uncertain outcomes and waits for an in-flight decision before reporting
  it. Missing/cross-scope request IDs are uniformly not_found.
- `pos_accept_web_order`: `p_request_id uuid`, `p_decision_id uuid`.
- `pos_reject_web_order`: those IDs plus required trimmed `p_reason text`
  (1–240 characters, no controls). Reason is staff-only in this slice; the existing
  customer status projection is unchanged.

Inbox success is `{ok:true,server_time,requests,has_more,next_cursor}`. Each request
contains only `request_id,status,customer:{name,phone},notes,created_at,expires_at,
totals:{currency_code,subtotal_minor,tax_total_minor,grand_total_minor},items,
canonical_order_id`. Items reuse the server-priced WEB-ORDERS snapshot shape.
Cursor is null or `{created_at,id}`. No capability hash, payload hash, raw token or
unneeded staff identifiers are returned. A targeted lookup returns one request.

Decision success is `{ok:true,request_id,status,canonical_order_id,decision_id,
replayed}`; canonical ID is nonnull only for acceptance. Fixed failure codes cover
invalid_session, permission_denied, not_found, request_expired, decision_conflict,
quote_changed, item_unavailable, modifier_selection_invalid, ordering_unavailable,
shift_required, order_rejected and invalid_request. Never expose SQL diagnostics.

## Atomic acceptance proof and implementation boundary

Authorization precedes terminal replay. Lock the scoped request before deciding and
sample real time after waits. A same-action replay returns the existing terminal
mapping without another canonical submission; an opposite decision conflicts.
Decision identities cannot be reused for another request or changed payload.

Lock the branch's tax/kitchen mode and published profile, prove its current branch
still equals the request's captured branch, and lock requested catalog parents and
children in deterministic order. Item/group FOR UPDATE locks block new child/FK
inserts, including an absent availability override. Lock inactive groups/options
as well so activation cannot race the quote. Reprice all IDs/quantities through
the existing authoritative helper and compare the complete quote components,
currency and each total. Refuse changed quotes; the customer must submit anew.

Construct exactly one canonical `order.submit` operation on the server, including
trusted item/modifier preparation snapshots and current canonical field names.
Call existing `app.sync_push` inside the acceptance transaction. This preserves
customer stamping, canonical audit, dispatch payload construction and printer-only
lifecycle behavior. Its outer ok is insufficient: require one matching operation,
inner ok=true, status=applied and the expected server-created canonical UUID.

The sync invocation, accepted mapping, decision ledger and final expiry check are
one rollback boundary. A failed/malformed inner result or later mapping/expiry
failure rolls back canonical rows, operation ledgers, audit and dispatch before a
safe refusal is returned. Unexpected DB faults propagate without diagnostic text
in the POS UI. Existing canonical RPC implementations/contracts are not replaced.
Concurrent catalog reparenting/reordering may produce a database deadlock or
serialization abort despite deterministic inbox lock order. Those whole-transaction
failures propagate as retryable uncertainty; recovery keeps the same decision ID.
No existing catalog writer is changed and no partial canonical effect may survive.
If this cannot be demonstrated, stop for the smallest architecture correction.
Rejection and expiry never call canonical submission or create dispatch.

## POS experience and containment

New model/repository/controller and responsive badge/sheet provide customer,
items/options, notes, quantities, integer-minor totals, age and expiry. Accept and
Reject are online-only, single-flight and use stable decision IDs. Uncertain writes
reconcile by targeted lookup and retry the same intent only. Pending requests never
enter the existing offline order outbox or canonical recent-order store. After a
successful acceptance refresh the existing canonical snapshot; do not submit or
print it again. Existing KDS/print drain/import/ack behavior remains authoritative.

Keep sensitive request data in memory only. Clear it immediately on PIN, device or
branch changes; discard stale async responses and stop background polling. Missing
hosted RPCs produce a localized unavailable state without breaking normal POS.
Arabic/Hebrew RTL and English LTR use the existing localization and currency paths.
No Storefront UI, protected reprint/renderer files or new payment behavior is added.

## Focused definition of done

SQL and two-session tests prove real device/PIN/role/scope/shift authority, revocation,
cross-tenant/branch denial, private-table denial, quote/config/availability races,
expiry during waits, Accept/Accept and Accept/Reject, inner-sync rejection, full
rollback, stable replay and exactly one canonical order/initial dispatch. Reject
and expiry prove zero operational effects. Relevant existing KDS/printer-only
chargeable/zero-total cases remain unchanged.

POS tests cover parsing, responsive/localized detail and actions, double taps,
loading/empty/expired/unavailable states, uncertain recovery, scope/session clearing
and canonical refresh. Run one focused cycle, fix actual findings, one independent
read-only review and normal CI. Open one PR; stop before merge or deployment.

Hosted release still requires separately authorized WEB-ORDERS and POS inbox
migrations. Customer submit function deployment, checkout integration and branch/
environment activation remain separate; ordering and delivery stay OFF.

## Implementation verification (2026-10-14)

- New pgTAP: 86 passed, including real canonical-sync execution followed by a
  deadline rollback and configured/absent preparation snapshots.
- Native two-connection harness: 11 controlled scenarios passed, including
  competing decisions, targeted-read waits, catalog/shift changes, expiry after
  waits and whole-transaction deadlock recovery with the same decision identity.
- Existing focused SQL: 475 passed (public ACL, tenant/policy coverage, WEB-ORDERS,
  device/PIN authorization, canonical RPC and printer-only lifecycle regressions).
- POS: 88 new repository/controller/widget tests, plus 185 existing menu/session/
  sync/notification/auth-gate/navbar tests passed. Geometry covers AR/HE/EN at phone,
  tablet and desktop widths and 1x/2x text. Localization checks cover matching ARB
  keys and RTL/LTR directionality.
- One independent read-only review approved with no Blocker/Major finding. Its
  minor badge-expiry observation was corrected and covered by a focused test.
- Normal CI passed all 298 SQL suites / 8,640 assertions and identified POS navbar
  height/brand-room regressions. The inbox shares the existing action cluster and
  the outbox width budget reserves the full symbol, including the drawer fixture;
  original height/brand assertions stayed intact. All 161 targeted navbar/responsive/
  drawer/inbox-widget checks passed after correction; no backend code changed.

Focused client command:

```sh
flutter test --no-pub apps/pos/test/online_order_inbox_repository_test.dart apps/pos/test/online_order_inbox_controller_test.dart apps/pos/test/online_order_inbox_widget_test.dart
```

The normal ephemeral Supabase CI runs `supabase/tests/pos_online_inbox_001_test.sql`.
The supplementary native harness is
`supabase/tests/support/run_pos_online_inbox_001_concurrency.mjs`; its header states
the strictly loopback, task-local disposable-cluster command. It never contacts a
linked/hosted project or operates on a real restaurant dataset.
