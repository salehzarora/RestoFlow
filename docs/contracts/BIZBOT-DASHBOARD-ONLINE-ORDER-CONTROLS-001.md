# BIZBOT-DASHBOARD-ONLINE-ORDER-CONTROLS-001

Local candidate based on `435ada86fe10c00c94c0fdfdb0395559587489eb`.
No hosted application, Git push, merge or production settings write is included.

## Branch contract

Three independent configured flags belong to the exact organization, restaurant
and branch: `ordering_enabled`, `alerts_enabled`, `printing_enabled`.
The existing 353 reader/setter remain unchanged for existing consumers.

New authenticated RPCs:

| RPC | Purpose |
| --- | --- |
| `get_online_order_settings_v2` | Authoritative branch configuration |
| `set_online_order_settings_v2` | Expected-revision, exact-intent update |
| `reconcile_online_order_settings_v2` | Read receipt and current state; never writes settings |

Every RPC takes `p_organization_id`, `p_restaurant_id`, `p_branch_id`.
Save and reconciliation additionally take `p_client_request_id` (UUID),
`p_expected_revision` (bigint, sent as canonical decimal text), and all three
boolean values. The server requires a real authenticated human identity and an
active downward-covering manager, restaurant-owner or organization-owner
membership. Cashiers, device/PIN authority and platform support do not substitute
for that authority. Wrong ancestry or uncovered branches return `not_found`.

Successful state includes `ok`, `entity: online_order_settings`, exact scope,
`provisioned`, three flags, `revision`, `print_generation`,
`containment_revision`, and optional operational intake-channel fields.
All counters are canonical decimal strings, including initial revision `"0"`.
Save adds `client_request_id`, `idempotent_replay`, and `no_change`.

The private append-only `app.online_order_settings_requests_v2` ledger binds
actor + UUID to a fingerprint of the complete typed intent. Exact replay returns
the original receipt before checking current revision. Different scope, values
or revision with that identity returns `request_conflict`. Valid authorized CAS
refusals are recorded; validation/authorization failures are not. No API role can
read or mutate this ledger directly; forced RLS, explicit revokes and private
helpers preserve the boundary.

Reconciliation returns `mutation_state: committed | refused | not_recorded`,
the original `result` if present, and separate fresh `current` settings.
`not_recorded` is a point-in-time observation, never cancellation or proof that
a delayed request cannot arrive. The UI keeps that unresolved UUID/intent and
offers receipt checking or an explicit resend of the identical intent only.
There is no automatic write retry. Committed/refused outcomes must be reconciled
before a new intent. A confirmed save is followed by a fresh authoritative read;
an old replay receipt never becomes the baseline for another manager's changes.

## Locking, audit and operational boundaries

V2 lock order is request fence -> existing containment fence -> active hierarchy
-> covering memberships -> settings -> existing intake channel -> private receipt.
Authority and revision
are checked after the locks. Legacy settings/containment writers share the
containment-first order; the feature ledger does not couple their shared
management-request locks. Configuration, intake-channel update, receipt and
before/after `settings.online_orders.updated` audit are one transaction.
An actual flag/containment transition advances revision; a true no-op does not.
The existing printing-generation rule is preserved: printing eligibility or
containment revision changes rotate generation. Other flags do not.

Publication, Pickup, hours, temporary pause, global notification operation,
device consent/registration/expiry and printer/containment readiness remain
independent gates. An intake change mirrors an existing channel only when the
configured intake flag actually changes. Alerts/printing/no-op saves preserve
separate channel state. A prepublication branch may have no channel; this API
does not create publication or a channel. Normal publication supplies its usual
channel while the configured intake flag continues to gate submission.

Existing POS consumer consequence: branch alerts OFF makes the existing alert
authority reader deny status. A background client that observes that denial
clears its local alert grant/opt-in and stops audio. This is not a direct update
to the hosted registration, but later turning the branch flag ON does not rearm
the device automatically. Authorized staff may need an ordinary foreground
enable again. Localized UI copy must explain this before Save. This behavior is
established from source, not a newly performed physical test; rollout approval
must acknowledge the consequence. This ticket does not change POS security
revocation handling or automatically restore consent/authority.

No setting change writes old requests/enrollment, registrations, notification
delivery records, holds, print history, leases or containment policy. Enabling
printing does not restore old-generation eligibility or authorize replay.
The 625 protected historical holds and UNKNOWN kitchen ticket are out of scope.

## Dashboard integration

The selected concrete branch receives one feature-owned Settings card through
the authenticated shell transport; support mode withholds that repository.
Switches edit a local draft, and only explicit Save submits a stable intent.
Loading, dirty, saving, denied, stale/conflicting, uncertain and confirmed-save
but failed-current-read states are visible. Branch changes invalidate late
responses. AR/HE/EN copy lives in the feature module to avoid Claude-owned shared
localization files; RTL/LTR, switch semantics, live notices and narrow/large-text
layout are covered. Existing Pickup/hours/pause controls are not duplicated.

## Validation and deployment dependencies

Focused Flutter repository/widget/integration and existing Settings/shell
regressions; rollback-only pgTAP permissions/behavior/invariant tests; independent
two-session manager/replay/reconciliation/rollback/legacy/containment/revocation
tests run only on disposable local fixtures. Captures are synthetic widget
renders, not production acceptance. Remote CI is pending owner-authorized push.

Future sequence, requiring separate authorization: review final source/security
-> one push and Draft PR/required CI/automatic Previews -> exact additive SQL
application and independent definition/ACL verification -> Dashboard web release
(product build also contains POS/KDS/Kiosk) -> explicitly scoped merchant
read/write verification. No Storefront, Edge or APK change is required.
Existing consumers can continue on v1 during rollout. Before backend rollout,
the new UI fails closed if v2 is absent; it never falls back to blind v1 writes.
Rollback the consumer independently; retain additive history, receipts and audit.

The current local deliverable authorizes none of those remote operations.
Payment PRs #370/#371, printer PRs #314/#315, their shared localization/ACL/docs,
merchant data and all physical devices remain outside this diff.
